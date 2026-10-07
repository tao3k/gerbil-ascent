---- MODULE OracleTransport ----
\* SPDX-FileCopyrightText: 2026 tao3k team and Contributors
\* SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
\* Two pipe readers and process/request completion; no generation bound.
EXTENDS Naturals, Sequences
CONSTANT Mutation
Channels == {"stdout","stderr"}
Expected(c) == IF c = "stdout" THEN <<0,1,2>> ELSE <<7,8>>
VARIABLES position, bytes, closed, failed, hardError,
          processDone, processOK, requestDone, requestOK, admitted
vars == <<position,bytes,closed,failed,hardError,processDone,processOK,requestDone,requestOK,admitted>>
Init == /\ position = [c \in Channels |-> 0] /\ bytes = [c \in Channels |-> <<>>]
  /\ closed = [c \in Channels |-> FALSE] /\ failed = closed /\ hardError = closed
  /\ processDone = FALSE /\ processOK = FALSE /\ requestDone = FALSE /\ requestOK = FALSE
  /\ admitted = FALSE
Live(c) == ~admitted /\ ~closed[c] /\ ~failed[c]
Read(c) == /\ Live(c) /\ position[c] < Len(Expected(c))
  /\ position' = [position EXCEPT ![c] = @ + 1]
  /\ bytes' = [bytes EXCEPT ![c] = IF Mutation = "tail" /\ position[c]+1 = Len(Expected(c))
                                  THEN @ ELSE Append(@,Expected(c)[position[c]+1])]
  /\ UNCHANGED <<closed,failed,hardError,processDone,processOK,requestDone,requestOK,admitted>>
EOF(c) == /\ Live(c) /\ position[c] = Len(Expected(c))
  /\ closed' = [closed EXCEPT ![c] = TRUE]
  /\ UNCHANGED <<position,bytes,failed,hardError,processDone,processOK,requestDone,requestOK,admitted>>
Error(c) == /\ Live(c) /\ failed' = [failed EXCEPT ![c] = TRUE]
  /\ hardError' = [hardError EXCEPT ![c] = TRUE]
  /\ UNCHANGED <<position,bytes,closed,processDone,processOK,requestDone,requestOK,admitted>>
Interrupt(c) == /\ Live(c)
  /\ failed' = [failed EXCEPT ![c] = IF Mutation = "interrupt" THEN TRUE ELSE @]
  /\ UNCHANGED <<position,bytes,closed,hardError,processDone,processOK,requestDone,requestOK,admitted>>
Exit(ok) == /\ ~admitted /\ ~processDone /\ processDone' = TRUE /\ processOK' = ok
  /\ UNCHANGED <<position,bytes,closed,failed,hardError,requestDone,requestOK,admitted>>
Send(ok) == /\ ~admitted /\ ~requestDone /\ requestDone' = TRUE /\ requestOK' = ok
  /\ UNCHANGED <<position,bytes,closed,failed,hardError,processDone,processOK,admitted>>
Admit == /\ ~admitted /\ processDone /\ processOK /\ requestDone /\ requestOK
  /\ (Mutation = "early" \/ \A c \in Channels : closed[c] \/ (Mutation = "swallow" /\ failed[c]))
  /\ (Mutation = "swallow" \/ \A c \in Channels : ~failed[c])
  /\ admitted' = TRUE
  /\ UNCHANGED <<position,bytes,closed,failed,hardError,processDone,processOK,requestDone,requestOK>>
Next == Admit \/ (\E ok \in BOOLEAN : Exit(ok) \/ Send(ok)) \/
  (\E c \in Channels : Read(c) \/ EOF(c) \/ Error(c) \/ Interrupt(c))
Spec == Init /\ [][Next]_vars
ReaderErrorSound == \A c \in Channels : failed[c] => hardError[c]
CompleteReaders == admitted => \A c \in Channels : closed[c]
ReaderClean == admitted => \A c \in Channels : ~failed[c]
CompleteBytes == admitted => \A c \in Channels : bytes[c] = Expected(c)
ExitAndRequest == admitted => processDone /\ processOK /\ requestDone /\ requestOK
====
