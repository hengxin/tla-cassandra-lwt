--------------------------- MODULE CassandraPaxos ---------------------------
EXTENDS Integers

Maximum(S) == 
  (*************************************************************************)
  (* If S is a set of numbers, then this define Maximum(S) to be the       *)
  (* maximum of those numbers, or -1 if S is empty.                        *)
  (*************************************************************************)
  IF S = {} THEN -1
            ELSE CHOOSE n \in S : \A m \in S : n \geq m
 
Same(S) ==
  (*************************************************************************)
  (* If S is not empty, then this define Same(S) to be the                 *)
  (* if or not the element of S is same.                                   *)
  (*************************************************************************)
  /\ S # {}
  /\  \E n \in S: \A m \in S : n = m          
            

CONSTANTS Value, Acceptor, Quorum, Data, ReadData
ASSUME  /\ \A Q \in Quorum : Q \subseteq Acceptor
        /\ \A Q1, Q2 \in Quorum : Q1 \cap Q2 /= {}
        /\ \A RD \in ReadData : RD \in Data
        
Ballot == Nat

None == CHOOSE v : v \notin Value

Message == 
       [type : {"Prepare"}, bal : Ballot]
  \cup [type : {"Promise"}, acc : Acceptor, bal : Ballot, 
        maxAccBal : Ballot \cup {-1}, maxAccVal : Value \cup {None},
        macComBal : Ballot \cup {-1}, maxComVal : Value \cup {None}]
  \cup [type : {"Read"}, bal : Ballot, data : Data]
  \cup [type : {"Result"}, bal : Ballot, data : Data, result : Value, 
                version: Nat, acc : Acceptor]
  \cup [type : {"Repair"}, data : Data, result : Value, version: Nat]
  \cup [type : {"Propose"}, bal : Ballot, val : Value]
  \cup [type : {"Accept"}, acc : Acceptor, bal : Ballot, val : Value]
  \cup [type : {"Commit"}, bal: Ballot, val: Value]
  \cup [type : {"Ack"}, acc : Acceptor, bal : Ballot,val : Value]

VARIABLES maxBal, maxAccBal, maxAccVal, maxComBal, maxComVal, msgs, dataResult  
vars == <<maxBal, maxAccBal, maxAccVal, maxComBal, maxComVal, msgs, dataResult>>

TypeOK == /\ maxBal  \in [Acceptor -> Ballot \cup {-1}]
          /\ maxAccBal \in [Acceptor -> Ballot \cup {-1}]
          /\ maxAccVal  \in [Acceptor -> Value \cup {None}]
          /\ maxComBal \in [Acceptor -> Ballot \cup {-1}]
          /\ maxComVal  \in [Acceptor -> Value \cup {None}]
          /\ msgs \subseteq Message
          /\ dataResult  \in [Acceptor -> [Data -> [result : Value, 
                                                    version : Nat]]]
                             
          
Init == /\ maxBal  = [a \in Acceptor |-> -1]
        /\ maxAccBal = [a \in Acceptor |-> -1]
        /\ maxAccVal  = [a \in Acceptor |-> None]
        /\ maxComBal = [a \in Acceptor |-> -1]
        /\ maxComVal  = [a \in Acceptor |-> None]
        /\ msgs = {}
        /\ dataResult  = [a \in Acceptor |->[data \in Data |-> [result |-> 0, 
                                                                version  |-> 0]]]
        
Send(m) == msgs' = msgs \cup {m}


Prepare(b) == /\ Send([type |-> "Prepare", bal |-> b])
              /\ UNCHANGED <<maxBal, maxAccBal, maxAccVal, maxComBal, 
                           maxComVal, dataResult>>
              
Promise(a) == 
  /\ \E m \in msgs : 
        /\ m.type = "Prepare"
        /\ m.bal > maxBal[a]
        /\ maxBal' = [maxBal EXCEPT ![a] = m.bal]
        /\ Send([type |-> "Promise", acc |-> a, bal |-> m.bal, 
                  maxAccBal |-> maxAccBal[a], maxAccVal |-> maxAccVal[a],
                  maxComBal |-> maxComBal[a], maxComVal |-> maxComVal[a]])
  /\ UNCHANGED <<maxAccBal, maxAccVal, maxComBal, maxComVal, dataResult>>

  
Propose(b,v) == /\ ~ \E m \in msgs: m.type = "Propose" /\ m.bal = b
                /\ \E Q \in Quorum :
                    LET Qmset == {m \in msgs : /\ m.type = "Promise"
                                               /\ m.acc \in Q
                                               /\ m.bal = b}
                        maxAbal == Maximum({m.maxAccBal : m \in Qmset})
                        maxCbal == Maximum({m.maxComBal : m \in Qmset})
                        \*如果存在未完成的提交，先propose未提交的值；如果可以提出自己的值，就需要read得到这个值
                        val == IF maxAbal > maxCbal 
                                THEN (CHOOSE m \in Qmset : m.maxAccBal = maxAbal).maxAccVal
                                ELSE v
                        \*这里应该有问题，我怎么得到需要去read的值？或者说我怎么选出我需要读取的值
                        rData== CHOOSE rd \in ReadData :TRUE
                    IN  /\ \A a \in Q : \E m \in Qmset : m.acc = a              
                        (****Read的data还不知道该怎么处理***)
                        /\ IF val=v  THEN Send([type |-> "Read", bal |-> b, data |-> rData])
                                     ELSE Send([type |-> "Propose",bal |-> b, val |-> val])
                /\ UNCHANGED<<maxBal, maxAccBal, maxAccVal, maxComBal, maxComVal, dataResult>>
            
            
Read(a) == /\ \E m \in msgs : /\ m.type = "Read" 
                              /\ Send([type |-> "Result", data |-> m.data, acc |-> a, bal |->m.bal,
                                       result |-> dataResult[a][m.data].result, 
                                       version |-> dataResult[a][m.data].version])
             /\ UNCHANGED <<maxBal, maxAccBal, maxAccVal, maxComBal, maxComVal,
                            dataResult>>
                          
Result(b) == /\ \E Q \in Quorum : 
                 LET QRmset == {m \in msgs : /\ m.type = "Result"
                                             /\ m.acc \in Q
                                             /\ m.bal = b }
                     QResult == {m.result : m \in QRmset}
                     \*如果读取到的结果不一致，需要开启修复，否则判断是否满足前置条件
                     res == IF Same(QResult) THEN CHOOSE n \in QResult : \A m \in QResult : n=m
                                             ELSE -1
                     ver == Maximum({m.version : m \in QRmset})
                     res2 == (CHOOSE m \in QRmset : m.version=ver).result
                 IN  /\ \A a \in Q : \E m \in QRmset : m.acc = a 
                     /\ IF res=-1 THEN Send([type |-> "Repair", result |-> res2, version |-> ver ])
                                  ELSE IF res \in Data THEN Send([type |-> "Propose", bal |-> b, val |-> res])
                                                       ELSE FALSE
                                                       
Repair(a) == /\ \E m \in msgs: /\ m.type="Repair"
                               /\ dataResult' = [dataResult EXCEPT ![a][m.data] = [result |-> m.result, version |-> m.version]]
             /\ UNCHANGED<<maxBal, maxAccBal, maxAccVal, maxComBal, maxComVal, msgs>>

         

Accept(a) == /\ \E m \in msgs: /\ m.type="Propose"
                               /\ maxBal[a] \leq m.bal
                               /\ maxBal' = [maxBal EXCEPT ![a] = m.bal]
                               /\ maxAccBal' = [maxAccBal EXCEPT ![a] = m.bal]
                               /\ maxAccVal' = [maxAccVal EXCEPT ![a] = m.val]
                               /\ Send([type |-> "Accept", bal |-> m.bal, val |-> m.val, 
                                       acc |->a])
             /\ UNCHANGED<<maxComBal, maxComVal, dataResult>>    

             
Commit(b,v) == /\ ~\E m \in msgs : m.type = "Commit" /\ m.bal = b
               /\ \E Q \in Quorum :
                   LET QAmset == {m \in msgs : /\ m.type="Accept"
                                               /\ m.acc \in Q
                                               /\ m.bal=b}
                   IN /\ \A a \in Q : \E m \in QAmset : m.acc = a
               /\ Send([type |-> "Commit", bal |-> b, val |-> v])
               /\ UNCHANGED <<maxBal, maxAccBal, maxAccVal, maxComBal, 
                             maxComVal, dataResult>>
               
Ack(a) == /\ \E m \in msgs: /\ m.type="Commit"
                            /\ maxBal[a] \leq m.bal
                            /\ maxBal' = [maxBal EXCEPT ![a] = m.bal]
                            /\ maxComBal' = [maxComBal EXCEPT ![a] = m.bal]
                            /\ maxComVal' = [maxComVal EXCEPT ![a] = m.val]
                            /\ Send([type |-> "Ack", bal |-> m.bal, val |-> m.val, 
                                    acc |->a])
          /\ UNCHANGED<<maxAccBal, maxAccVal, dataResult>>
          


Next == \/ \E b \in Ballot : \/ Prepare(b) 
                             \/ \E v \in Value : Propose(b,v) \/ Commit(b,v)
                             \/ Result(b)
                        
        \/ \E a \in Acceptor : \/ Promise(a) 
                               \/ Accept(a) 
                               \/ Ack(a)
                               \/ Read(a)
                               \/ Repair(a)                          
              
Spec == Init /\ [][Next]_vars
=============================================================================
\* Modification History
\* Last modified Wed Dec 15 15:07:23 CST 2021 by LENOVO
\* Created Thu Dec 08 10:19:29 CST 2021 by LENOVO