# Frozen direct-derivation annotations, branch search

Source text is returned external-model reasoning. Exact half-open Unicode character spans are validated. Definite repeats require an earlier grounded derivation with identical conclusion and ordered explicit premises; alternative witnesses and goal-dependent checks remain separate. Extraction is not independent human ground truth.

## paid/branch-search-6-baseline-0

Text SHA `bc99afdab7bc083a16964eb6160eb737b24df0a1a3c169d009b816e28cd806ae`; annotation failure `None`.

- Episode 0: derive; F0; span [449, 491]; prior None; definite repeat False; native truth False

> path 0->7 and 1->9. Edges: 0->2->4->7 yes.

- Episode 1: derive; F0; span [492, 532]; prior None; definite repeat False; native truth False

> 1->2->4->7->9 yes (1->2,2->4,4->7,7->9).

- Episode 2: derive; F1; span [544, 609]; prior None; definite repeat False; native truth False

> Option1 fragment 2: [2,4,11,5,9] => 4->11? edges 4->7->9->11 yes.

- Episode 3: derive; F1; span [616, 628]; prior None; definite repeat False; native truth False

> 5->7->9 yes.

- Episode 4: derive; F2; span [640, 684]; prior None; definite repeat False; native truth False

> Option2 fragment4: [4,1,7,6,11] => 1->7 yes;

- Episode 5: derive; F2; span [692, 718]; prior None; definite repeat False; native truth False

> 6->8->9->11 yes. eligible.

- Episode 6: derive; F3; span [755, 773]; prior None; definite repeat False; native truth False

> 3->8? 3->6->8 yes;

- Episode 8: uncertain; F4; span [796, 839]; prior None; definite repeat False; native truth False

> Option4 fragment8: [8,0,8,1,7] => 0->8 yes;

- Episode 9: uncertain; F4; span [840, 859]; prior None; definite repeat False; native truth False

> 1->7 yes. eligible.

- Episode 10: reuse; F4; span [2284, 2329]; prior None; definite repeat False; native truth False

> Fragment 8 need [0,0,8,1,7] both paths exist.

- Episode 11: derive; F0; span [3143, 3172]; prior None; definite repeat False; native truth False

> Path 0->7: 0->2->4->7 exists.

- Episode 12: derive; F0; span [3173, 3217]; prior None; definite repeat False; native truth False

> 1->9: 1->2->4->7->9 or 1->2->5->7->9 exists.

- Episode 13: derive; F2; span [3254, 3286]; prior None; definite repeat False; native truth False

> first 4->11: 4->7->9->11 exists.

- Episode 14: derive; F2; span [3287, 3315]; prior None; definite repeat False; native truth False

> second 5->9: 5->7->9 exists.

- Episode 15: derive; F4; span [3352, 3396]; prior None; definite repeat False; native truth False

> first 1->7: 1->2->4->7 or 1->2->5->7 exists.

- Episode 16: derive; F4; span [3397, 3430]; prior None; definite repeat False; native truth False

> second 6->11: 6->8->9->11 exists.

- Episode 17: derive; F6; span [3467, 3494]; prior None; definite repeat False; native truth False

> first 3->8: 3->6->8 exists.

- Episode 18: derive; F6; span [3495, 3522]; prior None; definite repeat False; native truth False

> second 9->11: 9->11 exists.

- Episode 20: derive; F1; span [9252, 9392]; prior None; definite repeat False; native truth True

> id5 fragment1: paths 2->9 and 3->11. 2->9: 2->4->7->9? edges 2->4,4->7,7->9 yes. 3->11: 3->6->8->9->11 (3->6,6->8,8->9,9->11) yes. Eligible.

- Episode 21: derive; F3; span [9394, 9507]; prior None; definite repeat False; native truth True

> id6 fragment3: 0->11 and 3->9. 0->11: 0->2->5->7->9->11 or 0->2->4->7->9->11 yes. 3->9: 3->6->8->9 yes. Eligible.

- Episode 22: derive; F5; span [9509, 9600]; prior None; definite repeat False; native truth True

> id7 fragment5: 2->7 and 8->11. 2->7: 2->4->7 or 2->5->7 yes. 8->11: 8->9->11 yes. Eligible.

- Episode 23: derive; F7; span [9602, 9694]; prior None; definite repeat False; native truth True

> id8 fragment7: 0->9 and 10->11. 0->9: 0->2->4->7->9 yes. 10->11: edge [10,11] yes. Eligible.

- Episode 24: derive; F9; span [9696, 9939]; prior None; definite repeat False; native truth False

> id9 fragment9: 3->7 and 2->9. 3->7: 3->6->8->9? need 7? Wait 3->7 direct? edges from 3: 3->6 only; 6->8, 8->9, 9->11. No path to 7? 7->9, but no incoming to 7 except 4,5. From 3 can't reach 7. So 3->7 does NOT exist. Thus fragment9 ineligible.

- Episode 25: derive; F2; span [14575, 14632]; prior None; definite repeat False; native truth True

> Path 4->11: 4->7->9->11 yes. 5->9: 5->7->9 yes. eligible.

- Episode 26: derive; F4; span [14633, 14773]; prior None; definite repeat False; native truth True

> 11 fragment 4: row [4,1,7,6,11]. First 1->7? edges 1->2 only, no path? 1->2->4->7 yes (or 5,7) yes. Second 6->11? 6->8->9->11 yes. eligible.

- Episode 27: derive; F6; span [14774, 14853]; prior None; definite repeat False; native truth True

> 12 fragment 6: row [6,3,8,9,11]. 3->8? 3->6->8 yes. 9->11 yes direct. eligible.

- Episode 28: derive; F0; span [14854, 14955]; prior None; definite repeat False; native truth True

> 13 fragment 0: row [0,0,7,1,9]. first 0->7: 0->2->4->7 yes. second 1->9: 1->2->5->7->9 yes. eligible.

- Episode 29: derive; F10; span [14956, 15190]; prior None; definite repeat False; native truth False

> 14 fragment 10: row [10,4,8,5,11]. 4->8? 4->7->9->? no edge to 8 from 9? edges 8->9,9->11, not 9->8. 4->7->9->11 no 8. Is there 4->7->? only 9->11. No path to 8. Also 5->11 yes 5->7->9->11. But first fails, inadmissible. So reject 14.

- Episode 30: mention; F3; span [24292, 24325]; prior None; definite repeat False; native truth False

> fragment 3: paths 0->11 and 3->9.

- Episode 31: derive; F3; span [24326, 24356]; prior None; definite repeat False; native truth False

> 0->11: edges 0->2->4->7->9->11

- Episode 33: derive; F3; span [24405, 24447]; prior None; definite repeat False; native truth False

> 3->9: 3->6->8->9 (edges 3-6,6-8,8-9). Yes.

- Episode 35: derive; F3; span [24443, 24457]; prior None; definite repeat False; native truth True

> Yes. Eligible.

- Episode 36: mention; F5; span [24459, 24502]; prior None; definite repeat False; native truth False

> Option 16 fragment 5: paths 2->7 and 8->11.

- Episode 37: derive; F5; span [24503, 24533]; prior None; definite repeat False; native truth False

> 2->7: 2->4->7 or 2->5->7. Yes.

- Episode 38: derive; F5; span [24534, 24555]; prior None; definite repeat False; native truth False

> 8->11: 8->9->11. Yes.

- Episode 39: derive; F5; span [24551, 24565]; prior None; definite repeat False; native truth True

> Yes. Eligible.

- Episode 40: mention; F7; span [24567, 24611]; prior None; definite repeat False; native truth False

> Option 17 fragment 7: paths 0->9 and 10->11.

- Episode 41: derive; F7; span [24612, 24636]; prior None; definite repeat False; native truth False

> 0->9: yes 0->2->4->7->9.

- Episode 42: derive; F7; span [24637, 24711]; prior None; definite repeat False; native truth False

> 10->11: edge 10->11 directly. Positive-length yes length 1 edge. Eligible.

- Episode 43: mention; F1; span [24713, 24756]; prior None; definite repeat False; native truth False

> Option 18 fragment 1: paths 2->9 and 3->11.

- Episode 44: derive; F1; span [24757, 24793]; prior None; definite repeat False; native truth False

> 2->9: 2->4->7->9 or 2->5->7->9. Yes.

- Episode 45: derive; F1; span [24794, 24821]; prior None; definite repeat False; native truth False

> 3->11: 3->6->8->9->11. Yes.

- Episode 46: derive; F1; span [24817, 24831]; prior None; definite repeat False; native truth True

> Yes. Eligible.

- Episode 47: mention; F11; span [24833, 24877]; prior None; definite repeat False; native truth False

> Option 19 fragment 11: paths 10->9 and 0->7.

- Episode 48: derive; F11; span [24878, 24972]; prior None; definite repeat False; native truth False

> 10->9? Edges from 10 only 10->11. Does 11 have outgoing? none listed. So 10->9 does not exist.

- Episode 49: derive; F11; span [24973, 25001]; prior None; definite repeat False; native truth False

> Thus fragment 11 ineligible.

- Episode 53: mention; FNone; span [27540, 27590]; prior None; definite repeat False; native truth False

> Need verify both paths for that fragment in edges.

- Episode 54: derive; F0; span [27701, 27882]; prior 28; definite repeat True; native truth True

> fragment 0: [0,0,7,1,9] => paths 0->7 and 1->9. Are both directed paths exist? 0->? edges: 0->2, 2->4/5, 4->7, so 0->2->4->7 yes. 1->9? 1->2->5->7->9 or 1->2->4->7->9 yes. Eligible.

- Episode 55: derive; F2; span [27883, 27966]; prior None; definite repeat False; native truth True

> fragment 2: [2,4,11,5,9] => 4->11 and 5->9. 4->7->9->11 yes. 5->7->9 yes. Eligible.

- Episode 56: derive; F4; span [27967, 28066]; prior 26; definite repeat True; native truth True

> fragment 4: [4,1,7,6,11] => 1->7, 6->11. 1->2->4->7 yes, 1->2->5->7 yes. 6->8->9->11 yes. Eligible.

- Episode 57: derive; F6; span [28067, 28141]; prior 27; definite repeat True; native truth True

> fragment 6: [6,3,8,9,11] => 3->8, 9->11. 3->6->8 yes. 9->11 yes. Eligible.

- Episode 58: derive; F8; span [28142, 28409]; prior None; definite repeat False; native truth False

> fragment 8: [8,0,8,1,7] => 0->8, 1->7. 0->2->4->7->9->... no 8? 0->2->? 2->4/5, 4->7->9->11, no 8. 0->2->? 2->? 2->4->7->9->? no 8. 0->2->? no path to 8 except? 8 reached from 6, 6 from 3. 0 no path to 3? 0->2 no 3. So 0->8 does not exist. Thus fragment 8 ineligible.

- Episode 59: mention; F6; span [29703, 29742]; prior None; definite repeat False; native truth False

> id21 seed cost55 <=56, risk28, value303

- Episode 60: derive; F5; span [31852, 31979]; prior None; definite repeat False; native truth True

> Option 25 frag5: [5,2,7,8,11] => paths 2->7 and 8->11. Both positive length. 2->4->7 exists yes. 8->9->11 exists yes. Eligible.

- Episode 61: derive; F7; span [33195, 33305]; prior 23; definite repeat True; native truth True

> Option 26 frag7: [7,0,9,10,11] => paths 0->9 and 10->11. 0->9? 0->2->4->7->9 yes. 10->11 yes direct. Eligible.

- Episode 62: derive; F1; span [33478, 33591]; prior 20; definite repeat True; native truth True

> Option 27 frag1: [1,2,9,3,11] => paths 2->9 and 3->11. 2->9? 2->4->7->9 yes. 3->11? 3->6->8->9->11 yes. Eligible.

- Episode 63: derive; F3; span [33699, 33815]; prior None; definite repeat False; native truth True

> Option 28 frag3: [3,0,11,3,9] => paths 0->11 and 3->9. 0->11? 0->2->4->7->9->11 yes. 3->9? 3->6->8->9 yes. Eligible.

- Episode 64: derive; F9; span [34084, 34300]; prior None; definite repeat False; native truth False

> Option 29 frag9: [9,3,7,2,9] => paths 3->7 and 2->9. 3->7? From 3 we have 3->6->8->9->11, no edge to 7; no path 3->7 because 6->8->9->11, 8->9->11, 9->11, 11 none. No 3->7. So first path absent. Therefore ineligible.

- Episode 65: mention; FNone; span [36197, 36233]; prior None; definite repeat False; native truth False

> Thus eligible children: 25,26,27,28.

- Episode 66: derive; F3; span [37278, 37495]; prior None; definite repeat False; native truth True

> Let's double-check eligibility for 28: fragment 3 needs [3,0,11,3,9]. Source edges directed. 0->11 path: 0->2->5->7->9->11? 2->5, 5->7, 7->9, 9->11 yes. 3->9 path: 3->6->8->9 yes. Both positive-length. Eligible. Good.

- Episode 67: derive; F6; span [38671, 38749]; prior 27; definite repeat True; native truth True

> Option 30: fragment 6: paths 3→8 and 9→11. 3→8: 3→6→8 yes. 9→11 yes. Eligible.

- Episode 68: derive; F0; span [40100, 40171]; prior None; definite repeat False; native truth True

> Option 31: fragment 0: paths 0→7 (yes via 2,4) and 1→9 (yes). Eligible.

- Episode 69: derive; F2; span [40173, 40252]; prior 55; definite repeat True; native truth True

> Option 32: fragment 2: paths 4→11 (4→7→9→11 yes) and 5→9 (5→7→9 yes). Eligible.

- Episode 70: derive; F4; span [40565, 40646]; prior None; definite repeat False; native truth True

> Option 33: fragment 4: paths 1→7 (yes 1→2→4→7) and 6→11 (6→8→9→11 yes). Eligible.

- Episode 71: derive; F10; span [40736, 40954]; prior None; definite repeat False; native truth False

> Option 34: fragment 10: paths 4→8 (4→7→9→11... 4→8? 4→7→9→... no edge to 8. From 4: 7,9,11. No 8. So 4→8 does NOT exist). Second 5→11 (5→7→9→11 yes). Since only one path exists, not eligible. So option 34 inadmissible.

- Episode 72: derive; F6; span [45210, 45347]; prior 67; definite repeat True; native truth True

> Let me double check eligibility of fragment 6: firstFrom 3 firstTo 8: path 3→6→8 exists. secondFrom 9 secondTo 11: 9→11 exists. Yes both.

- Episode 73: derive; F0; span [45928, 46180]; prior None; definite repeat False; native truth True

> frag0: [0,0,7,1,9] => firstFrom=0 firstTo=7, secondFrom=1 secondTo=9. Need positive-length directed paths 0->7 and 1->9 in edges.
> Edges directed? [0,2], [2,4],[4,7] gives 0->2->4->7 yes. 1->2->4->7->9 yes (1->2 edge, 2->4,4->7,7->9). So frag0 eligible.

- Episode 74: derive; F2; span [46182, 46264]; prior 25; definite repeat True; native truth True

> frag2: [2,4,11,5,9] => 4->11? Edges: 4->7->9->11 yes. 5->9? 5->7->9 yes. Eligible.

- Episode 75: derive; F4; span [46266, 46350]; prior 70; definite repeat True; native truth True

> frag4: [4,1,7,6,11] => 1->7 yes 1->2->4->7. 6->11? Edges: 6->8->9->11 yes. Eligible.

- Episode 76: derive; F10; span [46352, 46486]; prior None; definite repeat False; native truth False

> frag10: [10,4,8,5,11] => 4->8? Edges: 4->7->9->11, no 8. 4->? no to 8. 5->11 yes 5->7->9->11. First path 4->8 absent. So inadmissible?

- Episode 78: derive; F2; span [48970, 49063]; prior 74; definite repeat True; native truth True

> F2: row [2,4,11,5,9]: first 4->11? Edges 4->7->9->11 yes. second 5->9? 5->7->9 yes. eligible.

- Episode 79: derive; F10; span [49065, 49360]; prior 76; definite repeat False; native truth False

> F10: row [10,4,8,5,11]: first 4->8? Edges 4->7->9->11? no 8. Or 4->7->9? no 8. Edges have 3->6->8, 6->8, but from 4 no path to 8? 4->7->9->11; 9->11; no 8. So first path 4->8 does not exist. Thus F10 ineligible. Actually also second 5->11 exists via 5->7->9->11. But both required so ineligible.

- Episode 80: derive; F2; span [52420, 52464]; prior None; definite repeat False; native truth False

> Check path 4→11: edges 4→7→9→11. Yes exists.

- Episode 81: derive; F2; span [52465, 52493]; prior None; definite repeat False; native truth False

> Path 5→9: 5→7→9. Yes exists.

- Episode 82: derive; F2; span [52495, 52518]; prior None; definite repeat False; native truth True

> So fragment 2 eligible.

- Episode 83: uncertain; F10; span [52621, 52666]; prior None; definite repeat False; native truth False

> Path 4→8: edges 4→7→9→... 9→11. No path to 8.

- Episode 84: derive; F10; span [52737, 52748]; prior None; definite repeat False; native truth True

> Ineligible.

- Episode 85: reuse; F2; span [52750, 52793]; prior None; definite repeat False; native truth False

> So choose option 32 (fragment 2), eligible.

- Episode 86: mention; F10; span [54130, 54226]; prior None; definite repeat False; native truth False

> Need fragment F=10 needs row: [10,4,8,5,11] i.e paths 4->8 and 5->11 must exist in source edges.

- Episode 87: derive; F10; span [54318, 54426]; prior None; definite repeat False; native truth False

> Path 4->8? edges from 4 to7,7->9,9->11, maybe no 8. 6->8, but reach 4->7->9->11, can't go 8. No path 4 to 8.

- Episode 88: reuse; F10; span [54427, 54455]; prior None; definite repeat False; native truth True

> Thus fragment 10 ineligible.

- Episode 89: derive; F5; span [55352, 55467]; prior 60; definite repeat True; native truth True

> id25 fragment5: needs [2->7, 8->11]. Check directed paths.
> Edges: 2->4->7 yes 2 to7. 8->9->11 yes 8 to11. Eligible.

- Episode 90: derive; F7; span [55468, 55552]; prior 23; definite repeat True; native truth True

> id26 fragment7: [0->9, 10->11]. 0->2->4->7->9 yes 0->9. 10->11 direct yes. Eligible.

- Episode 91: derive; F1; span [55553, 55635]; prior 20; definite repeat True; native truth True

> id27 fragment1: [2->9, 3->11]. 2->4->7->9 yes. 3->6->8->9->11 yes 3->11. Eligible.

- Episode 92: derive; F9; span [55636, 55766]; prior None; definite repeat False; native truth False

> id29 fragment9: [3->7, 2->9]. 3->6->8->9? 3 to7? edges 3->6->8->9, no edge to7. 3->6,6->8,8->9, no 7. So 3->7 fails. Not eligible.

- Episode 93: derive; F7; span [60928, 61054]; prior 90; definite repeat True; native truth True

> But check fragment eligibility for id26 fragment7: needs [0,9] and [10,11]. Edges: 0->2->4->7->9 yes; 10->11 yes. So eligible.

- Episode 94: derive; F6; span [62384, 62472]; prior 27; definite repeat True; native truth True

> 30 fragment 6: paths 3->8, 9->11. Edges: 3->6,6->8 yes 3->8. 9->11 direct yes. Eligible.

- Episode 95: derive; F0; span [62473, 62572]; prior None; definite repeat False; native truth True

> 31 fragment 0: paths 0->7, 1->9. 0->2->5->7? edges 0->2,2->5,5->7 yes. 1->2->5->7->9 yes. Eligible.

- Episode 96: derive; F2; span [62573, 62646]; prior 55; definite repeat True; native truth True

> 32 fragment 2: paths 4->11, 5->9. 4->7->9->11 yes. 5->7->9 yes. Eligible.

- Episode 97: derive; F4; span [62647, 62723]; prior None; definite repeat False; native truth True

> 33 fragment 4: paths 1->7, 6->11. 1->2->5->7 yes. 6->8->9->11 yes. Eligible.

- Episode 98: derive; F10; span [62724, 63009]; prior None; definite repeat False; native truth True

> 34 fragment 10: paths 4->8, 5->11. 4->7->9->11? for 5->11: 5->7->9->11 yes. 4->8: 4->7->9->11? no, 4->7->9 then maybe 8? edge 8->9, but no 9->8. 4->8 path? 4->7, 7->9, 9->11, no to 8. 4->8? edges from 4 only 4->7. 7->9. 9->11. No 8. So 4->8 does NOT exist. Thus fragment 10 ineligible.

- Episode 99: derive; F6; span [73795, 73890]; prior 94; definite repeat True; native truth True

> Let's verify fragment 6 paths: 3->8 and 9->11. Edges: 3->6,6->8 exists. 9->11 exists. Eligible.

- Episode 100: derive; F0; span [75574, 75591]; prior None; definite repeat False; native truth False

> 0->2->4->7 exists

- Episode 102: derive; F0; span [75646, 75666]; prior None; definite repeat False; native truth True

> Fragment 0 eligible.

- Episode 103: derive; F2; span [75685, 75713]; prior None; definite repeat False; native truth False

> first 4->11: 4->7->9->11 yes

- Episode 104: derive; F2; span [75715, 75739]; prior None; definite repeat False; native truth False

> second 5->9: 5->7->9 yes

- Episode 106: derive; F4; span [75769, 75809]; prior None; definite repeat False; native truth False

> first 1->7: 1->2->5->7 or 1->2->4->7 yes

- Episode 107: derive; F4; span [75811, 75840]; prior None; definite repeat False; native truth False

> second 6->11: 6->8->9->11 yes

- Episode 109: derive; F10; span [75884, 75992]; prior None; definite repeat False; native truth False

> Edges: 4->7->9->11, no path to 8? 8 is predecessor to 9 only; no edge to 8 except 6->8. So 4 cannot reach 8.

- Episode 110: derive; F10; span [75993, 76022]; prior None; definite repeat False; native truth False

> second 5->11: 5->7->9->11 yes

- Episode 111: derive; F10; span [76024, 76070]; prior None; definite repeat False; native truth True

> Fragment 10 NOT eligible (first path missing).

- Episode 112: derive; F2; span [78520, 78794]; prior None; definite repeat False; native truth False

> fragment 2: [2,4,11,5,9] → first path 2→4, second 5→9. Edges: [2,4] exists, [5,9]? edges list: [2,4],[2,5],[4,7],[5,7]... no [5,9]. Hmm, secondFrom 5, secondTo 9. Edges have [5,7],[7,9], so 5→9 is a path of length 2. Path exists (positive-length directed path). So eligible.

- Episode 113: derive; F4; span [78797, 78922]; prior 70; definite repeat True; native truth True

> fragment 4: [4,1,7,6,11] → first 1→7, second 6→11. Edges: 1→2→...→7? 1→2,2→4,4→7 yes path. 6→11? 6→8→9→11 yes path. Eligible.

- Episode 114: derive; F10; span [78925, 79080]; prior None; definite repeat False; native truth False

> fragment 10: [10,4,8,5,11] → first 10→4? Edges: 10→11 only; no path 10→4 (10→11, 11 no outgoing). Not eligible. second 5→11: 5→7→9→11 yes. But first fails.

- Episode 115: derive; F2; span [79853, 80112]; prior None; definite repeat False; native truth False

> For fragment 2: need [2,4,11,5,9]. Check edges: [4,11]? Source edges list: [0,2],[1,2],[2,4],[2,5],[4,7],[5,7],[3,6],[6,8],[7,9],[8,9],[9,11],[10,11]. Edge 4->11? Not present. Edge 4->7, 7->9, 9->11, so path 4->7->9->11 exists (positive length directed path).

- Episode 116: derive; F2; span [80113, 80154]; prior None; definite repeat False; native truth False

> Second path 5->9? Edge 5->7, 7->9 exists.

- Episode 117: derive; F2; span [80155, 80288]; prior 55; definite repeat True; native truth True

> So both paths exist? firstFrom=4 firstTo=11: path 4->7->9->11 yes. secondFrom=5 secondTo=9: path 5->7->9 yes. So fragment 2 eligible.

- Episode 118: mention; F10; span [80290, 80470]; prior None; definite repeat False; native truth False

> For fragment 10: need [10,4,8,5,11]? Wait columns: [fragmentId, firstFrom, firstTo, secondFrom, secondTo]. Row: [10,4,8,5,11] means fragment 10: first path 4->8, second path 5->11.

- Episode 119: derive; F10; span [80471, 80535]; prior None; definite repeat False; native truth False

> Check 4->8? Edges from 4: 4->7 only. 7->9->11 or 7->9->... no 8.

- Episode 120: derive; F10; span [80536, 80591]; prior None; definite repeat False; native truth False

> 5->? 5->7 only. 7->9->11, so 5->11 yes via 5->7->9->11.

- Episode 121: derive; F10; span [80592, 80629]; prior 119; definite repeat False; native truth False

> But 4->8? No path? 4->7->9->11, no 8.

- Episode 122: derive; F10; span [80648, 80674]; prior None; definite repeat False; native truth False

> So fragment 10 ineligible.

- Episode 123: derive; F10; span [81555, 81660]; prior None; definite repeat False; native truth False

> Path 4->8? Edges 4->7, 7->9, 8->9 no 9->8. No path 4 to 8. Directed from 4: 4->7->9->11. 8 only incoming.

Rejected labels retained:
[{"annotation":{"claim":"There is a directed path from 9 to 11 for fragment 6, witnessed directly by edge 9->11.","explanation":"Explicit direct edge derivation for second path need of fragment 6.","fragment":3,"kind":"derive","occurrence":0,"paths":[[9,11]],"premiseEdges":[[9,11]],"prior":null,"quote":"9->11 yes. eligible.","ready":null},"chunkFirstCall":0,"failure":"out of chronological order","index":7},{"annotation":{"claim":"Both path requirements for fragment 4 exist, so fragment 4 is eligible.","explanation":"Explicit conjunction eligibility for fragment 4 with both edge-chain supports.","fragment":"null","kind":"derive","occurrence":0,"paths":[[1,7],[6,11]],"premiseEdges":[[1,2],[2,4],[4,7],[6,8],[8,9],[9,11]],"prior":null,"quote":"needs [4,1,7,6,11]. firstFrom1 firstTo7 path 1->2->4->7 (or 1->2->5->7) exists; secondFrom6 secondTo11 path 6->8->9->11 exists. eligible.","ready":true},"chunkFirstCall":0,"failure":"unknown fragment","index":19},{"annotation":{"claim":"confirms 0->11 via edges 0-2,2-4,4-7,7-9,9-11","explanation":"References the previously stated edge chain for 0->11 without redrawing the inference.","fragment":3,"kind":"reuse","occurrence":0,"paths":[[0,11]],"premiseEdges":[[0,2],[2,4],[4,7],[7,9],[9,11]],"prior":1,"quote":"Yes 0-2,2-4,4-7,7-9,9-11.","ready":null},"chunkFirstCall":4,"failure":"repeat link must connect derivations","index":2},{"annotation":{"claim":"option 15 fragment 3 requires paths 0->11 and 3->9","explanation":"Lists the required pair for fragment 3 without concluding eligibility.","fragment":3,"kind":"mention","occurrence":0,"paths":[[0,11],[3,9]],"premiseEdges":[],"prior":null,"quote":"Option 15 fragment 3: paths 0->11 and 3->9.","ready":null},"chunkFirstCall":4,"failure":"out of chronological order","index":4},{"annotation":{"claim":"eligibility requires both positive-length directed paths exist","explanation":"States the general eligibility rule for both paths.","fragment":null,"kind":"mention","occurrence":0,"paths":[],"premiseEdges":[],"prior":null,"quote":"Need check eligibility: both positive-length directed paths of fragment must exist in source edges.","ready":null},"chunkFirstCall":4,"failure":"out of chronological order","index":20},{"annotation":{"claim":"both positive-length directed paths must exist","explanation":"Restates the general two-path rule.","fragment":null,"kind":"mention","occurrence":0,"paths":[],"premiseEdges":[],"prior":null,"quote":"Need both positive-length directed paths exist.","ready":null},"chunkFirstCall":4,"failure":"out of chronological order","index":21},{"annotation":{"claim":"fragment 5 paths 2->7 and 8->11 both exist","explanation":"References the already-established eligibility of fragment 5 without redrawing the edge-chain proof.","fragment":5,"kind":"reuse","occurrence":0,"paths":[[2,7],[8,11]],"premiseEdges":[],"prior":8,"quote":"fragment 5 paths 2->7 and 8->11, both exist.","ready":true},"chunkFirstCall":4,"failure":"repeat link must connect derivations","index":22},{"annotation":{"claim":"Fragment 0 requires 0->7 and 1->9; both directed paths exist, so fragment 0 is eligible","explanation":"Same fragment path conclusion and same source-bound qualification; qualifies as a repeated source-bound derivation across calls, with a different witness chain for 1->9.","fragment":0,"kind":"derive","occurrence":0,"paths":[[0,7],[1,9]],"premiseEdges":[[0,2],[2,4],[4,7],[1,2],[2,5],[5,7],[7,9]],"prior":0,"quote":"F0: need [0,0,7,1,9]? Wait needs rows indexed fragment id. fragment 0: [0,0,7,1,9] means first path 0->7, second 1->9. Source edges: 0->2, 2->4/5, 4->7 yes 0-2-4-7 exists. 1->2->5->7->9 exists. eligible yes.","ready":true},"chunkFirstCall":8,"failure":"different conclusion/premise context","index":4},{"annotation":{"claim":"Path 1->2->5->7->9 exists for fragment 0 second path.","explanation":"Specific ordered edge-chain witness for fragment 0 second path.","fragment":0,"kind":"derive","occurrence":0,"paths":[[1,9]],"premiseEdges":[[1,2],[2,5],[5,7],[7,9]],"prior":null,"quote":"1->2->5->7->9 yes","ready":null},"chunkFirstCall":14,"failure":"quote not present verbatim","index":1},{"annotation":{"claim":"Fragment 2 is eligible because both required directed paths exist.","explanation":"Conjunction conclusion immediately after deriving both 4->11 and 5->9 paths.","fragment":2,"kind":"derive","occurrence":0,"paths":[[4,11],[5,9]],"premiseEdges":[],"prior":null,"quote":"eligible.","ready":true},"chunkFirstCall":14,"failure":"out of chronological order","index":5},{"annotation":{"claim":"Fragment 4 is eligible because both required directed paths exist.","explanation":"Conjunction conclusion based on just-derived 1->7 and 6->11 paths.","fragment":4,"kind":"derive","occurrence":1,"paths":[[1,7],[6,11]],"premiseEdges":[],"prior":null,"quote":"eligible.","ready":true},"chunkFirstCall":14,"failure":"out of chronological order","index":8},{"annotation":{"claim":"Restating both fragment 2 required paths exist","explanation":"Reuse of the earlier fragment 2 verification without re-deriving edges.","fragment":2,"kind":"reuse","occurrence":0,"paths":[[4,11],[5,9]],"premiseEdges":[],"prior":null,"quote":"So both paths exist? firstFrom=4 firstTo=11: path 4->7->9->11 yes. secondFrom=5 secondTo=9: path 5->7->9 yes.","ready":null},"chunkFirstCall":16,"failure":"out of chronological order","index":9}]

## paid/branch-search-6-baseline-1

Text SHA `2da921cbfaa186b9c7b856c7a8daaf847e0c1d12326d4879a0d82f0bafeb3b43`; annotation failure `None`.

- Episode 0: derive; F0; span [760, 855]; prior None; definite repeat False; native truth True

> 0->2->? 2->4->7 yes 0->2->4->7 exists. 1->2->4->7->9 yes 1->2->4->7->9 exists. eligible likely.

- Episode 1: derive; F1; span [856, 929]; prior None; definite repeat False; native truth True

> fragment 2: 2->9 and 3->11. 2->4->7->9 yes. 3->6->8->9->11 yes. eligible.

- Episode 2: derive; F2; span [930, 997]; prior None; definite repeat False; native truth True

> fragment 4: 4->11 and 5->9. 4->7->9->11 yes. 5->7->9 yes. eligible.

- Episode 3: derive; F3; span [998, 1074]; prior None; definite repeat False; native truth True

> fragment 6: 0->11 and 3->9. 0->2->4->7->9->11 yes. 3->6->8->9 yes. eligible.

- Episode 4: derive; F4; span [1075, 1145]; prior None; definite repeat False; native truth True

> fragment 8: 1->7 and 6->11. 1->2->4->7 yes. 6->8->9->11 yes. eligible.

- Episode 5: reuse; F4; span [3353, 3424]; prior None; definite repeat False; native truth False

> Need check eligibility fragment4: both paths 4->11 and 5->9 exist. Yes.

- Episode 6: uncertain; F1; span [3980, 4072]; prior None; definite repeat False; native truth False

> Fragment 1: need row [1,2,9,3,11]. Edges: 2->9? Not present. 3->11? Not present. Ineligible.

- Episode 7: uncertain; F3; span [4074, 4148]; prior None; definite repeat False; native truth False

> Fragment 3: [3,0,11,3,9]. 0->11 not present, 3->9 not present. Ineligible.

- Episode 8: uncertain; F5; span [4150, 4226]; prior None; definite repeat False; native truth False

> Fragment 5: [5,2,7,8,11]. 2->7? edges: 2->4,2->5. No. 8->11? no. Ineligible.

- Episode 9: uncertain; F7; span [4228, 4310]; prior None; definite repeat False; native truth False

> Fragment 7: [7,0,9,10,11]. 0->9? no. 10->11? yes present. First fails. Ineligible.

- Episode 10: uncertain; F9; span [4312, 4368]; prior None; definite repeat False; native truth True

> Fragment 9: [9,3,7,2,9]. 3->7? no. 2->9? no. Ineligible.

- Episode 11: derive; F5; span [6234, 6386]; prior None; definite repeat False; native truth True

> 2->7: is there path 2->5->7, yes! 2->5 and 5->7 present. So path exists. Second 8->11: is there path 8->11? 8->9, 9->11, yes! So fragment 5 is eligible.

- Episode 12: derive; F1; span [6435, 6510]; prior None; definite repeat False; native truth True

> Fragment 1: 2->9: path 2->5->7->9 yes. 3->11: 3->6->8->9->11 yes. Eligible!

- Episode 13: derive; F3; span [6512, 6585]; prior None; definite repeat False; native truth True

> Fragment 3: 0->11: 0->2->4->7->9->11 yes. 3->9: 3->6->8->9 yes. Eligible!

- Episode 14: derive; F7; span [6587, 6653]; prior None; definite repeat False; native truth True

> Fragment 7: 0->9: 0->2->5->7->9 yes. 10->11: 10->11 yes. Eligible!

- Episode 15: uncertain; F9; span [6655, 6736]; prior None; definite repeat False; native truth True

> Fragment 9: 3->7: 3->6->8... 8->9, no 7. 3->6->8->9->11 no path to 7. Ineligible?

- Episode 16: reuse; F7; span [8802, 8923]; prior None; definite repeat False; native truth True

> Option 7 gives value318, cost52, risk32 — good. Fragment7 needs [7,0,9,10,11]: path 0->9 exists, 10->11 exists. Eligible.

- Episode 17: derive; F2; span [10821, 10936]; prior 2; definite repeat True; native truth True

> fragment 2 (option id10): first 4->11? Edges: 4->7,7->9,9->11, so yes. second 5->9? Edges: 5->7,7->9 yes. Eligible.

- Episode 18: derive; F4; span [10938, 11079]; prior 4; definite repeat True; native truth True

> fragment 4 (id11): 1->7? Edges from 1->2, 2->4 or 5, 4->7 or 5->7. 1->2->4->7 yes. second 6->11? 6->8->9->11 yes (6->8,8->9,9->11). Eligible.

- Episode 19: derive; F6; span [11081, 11139]; prior None; definite repeat False; native truth True

> fragment 6 (id12): 3->8? 3->6->8 yes. 9->11 yes. Eligible.

- Episode 20: derive; F0; span [11141, 11247]; prior 0; definite repeat True; native truth True

> fragment 0 (id13): 0->7? 0->2->4->7 or 0->2->5->7 yes. 1->9? 1->2->4->7->9 or 1->2->5->7->9 yes. Eligible.

- Episode 21: derive; F10; span [11249, 11462]; prior None; definite repeat False; native truth False

> fragment 10 (id14): 4->8? Edges: 4->7,7->9,9->11, no 8. Does any path 4->...->8? 4->7->9->11 dead; no. So not eligible (first path missing). Also second 5->11? 5->7->9->11 yes, but first fails. So id14 ineligible.

- Episode 22: derive; F3; span [17667, 17852]; prior 3; definite repeat True; native truth True

> id15 fragment3: needs row [3,0,11,3,9]? Actually rows: [3,0,11,3,9]. Need path 0->11 and 3->9. Edges: 0->2, 2->4,4->7,7->9,9->11 so 0->11 yes via 0-2-4-7-9-11; 3->6->8->9 yes. Eligible.

- Episode 23: derive; F5; span [17854, 17979]; prior None; definite repeat False; native truth True

> id16 fragment5: needs row [5,2,7,8,11]. Need 2->7 yes (2->4->7 or 2->5->7); 8->11? edges 8->9->11 yes (8->9,9->11). Eligible.

- Episode 24: derive; F7; span [17981, 18083]; prior None; definite repeat False; native truth True

> id17 fragment7: needs row [7,0,9,10,11]. Need 0->9 yes (0->2->4->7->9); 10->11 yes (10->11). Eligible.

- Episode 25: derive; F1; span [18085, 18194]; prior 1; definite repeat True; native truth True

> id18 fragment1: needs row [1,2,9,3,11]. Need 2->9? edges 2->4->7->9 yes. 3->11? 3->6->8->9->11 yes. Eligible.

- Episode 26: derive; F11; span [18196, 18398]; prior None; definite repeat False; native truth False

> id19 fragment11: needs row [11,10,9,0,7]. Need 10->9? Edges: 10->11 only, no edge 10->9; maybe 10->11 cannot go to 9 (no). So path 10->9 does not exist. Thus fragment11 ineligible. So id19 inadmissible.

- Episode 27: derive; F4; span [25150, 25380]; prior 4; definite repeat True; native truth True

> So fragment 4 needs firstFrom=1 firstTo=7, secondFrom=6 secondTo=11. Need paths 1->7 and 6->11 in source edges. Edges: [1,2],[2,4],[4,7] gives 1->2->4->7 yes. 6->8->9->11? edges [6,8],[8,9],[9,11] yes. So option20 eligible likely.

- Episode 28: derive; F6; span [25382, 25536]; prior 19; definite repeat True; native truth True

> 21 fragment 6: needs [3,8,9,11]? Wait row 6 [6,3,8,9,11] -> first 3->8, second 9->11. Edges: 3->6? [3,6], 6->8 yes 3->6->8. 9->11 direct [9,11]. Eligible.

- Episode 29: derive; F0; span [25538, 25690]; prior 0; definite repeat True; native truth True

> 22 fragment 0: needs [0,7,1,9]. Path 0->7? edges from 0 none except? [0,2] only. Need 0 to 7: 0->2->4->7 yes. 1->9: 1->2->4->7->9 yes (or 5?). Eligible.

- Episode 30: derive; F2; span [25692, 25777]; prior 2; definite repeat True; native truth True

> 23 fragment 2: needs [4,11,5,9]. 4->11: 4->7->9->11 yes. 5->9: 5->7->9 yes. Eligible.

- Episode 31: derive; F8; span [25779, 25996]; prior None; definite repeat False; native truth True

> 24 fragment 8: needs [0,8,1,7]. 0->8: 0->2->4->7->9? no to 8? Need 0->2->? edge 2->? no to 8. Could be 0->2->4->7->9->11 only, no 8. Maybe 0->2->... no. 0->8 no because edge to 8 from 6 only. So fragment 8 ineligible.

- Episode 32: derive; F5; span [30003, 30112]; prior None; definite repeat False; native truth True

> Fragment 5: [5,2,7,8,11] need 2->7 and 8->11.
> 2->7: 2->4->7 or 2->5->7 yes.
> 8->11: 8->9->11 yes. So eligible.

- Episode 33: derive; F7; span [30341, 30435]; prior 24; definite repeat True; native truth True

> Fragment 7: [7,0,9,10,11] need 0->9 and 10->11.
> 0->9: 0->2->4->7->9 yes. 10->11 yes. Eligible.

- Episode 34: derive; F1; span [30554, 30658]; prior 1; definite repeat True; native truth True

> Fragment 1: [1,2,9,3,11] need 2->9 and 3->11.
> 2->9: 2->4->7->9 yes. 3->11: 3->6->8->9->11 yes. Eligible.

- Episode 35: derive; F3; span [30749, 30856]; prior 3; definite repeat True; native truth True

> Fragment 3: [3,0,11,3,9] need 0->11 and 3->9.
> 0->11: 0->2->4->7->9->11 yes. 3->9: 3->6->8->9 yes. Eligible.

- Episode 36: derive; F9; span [31025, 31211]; prior None; definite repeat False; native truth True

> Fragment 9: [9,3,7,2,9] need 3->7 and 2->9.
> 3->7: 3->6->8->9? that's 3->...->9 not 7. No edge to 7 except 4->7,5->7. No path 3->7. So ineligible. Option 29 fragment9 inadmissible likely.

- Episode 37: derive; F0; span [32931, 33033]; prior None; definite repeat False; native truth True

> fragment 0: [0,0,7,1,9] → path 0→7 and 1→9. Edges: 0→2→4→7 yes (0-2,2-4,4-7). 1→2→5→7→9 yes. Eligible.

- Episode 38: derive; F1; span [33036, 33115]; prior 1; definite repeat True; native truth True

> fragment 1: [1,2,9,3,11] → 2→9 and 3→11. 2→4→7→9 yes. 3→6→8→9→11 yes. Eligible.

- Episode 39: derive; F2; span [33118, 33193]; prior None; definite repeat False; native truth True

> fragment 2: [2,4,11,5,9] → 4→11 and 5→9. 4→7→9→11 yes. 5→7→9 yes. Eligible.

- Episode 40: derive; F3; span [33196, 33276]; prior None; definite repeat False; native truth True

> fragment 3: [3,0,11,3,9] → 0→11 and 3→9. 0→2...→9→11 yes. 3→6→8→9 yes. Eligible.

- Episode 41: derive; F4; span [33279, 33356]; prior None; definite repeat False; native truth True

> fragment 4: [4,1,7,6,11] → 1→7 and 6→11. 1→2→5→7 yes. 6→8→9→11 yes. Eligible.

- Episode 42: derive; F5; span [33359, 33432]; prior 23; definite repeat True; native truth True

> fragment 5: [5,2,7,8,11] → 2→7 and 8→11. 2→4→7 yes. 8→9→11 yes. Eligible.

- Episode 43: derive; F6; span [33435, 33506]; prior 19; definite repeat True; native truth True

> fragment 6: [6,3,8,9,11] → 3→8 and 9→11. 3→6→8 yes. 9→11 yes. Eligible.

- Episode 44: derive; F7; span [33509, 33587]; prior 24; definite repeat True; native truth True

> fragment 7: [7,0,9,10,11] → 0→9 and 10→11. 0→2→4→7→9 yes. 10→11 yes. Eligible.

- Episode 45: derive; F8; span [33590, 33772]; prior None; definite repeat False; native truth False

> fragment 8: [8,0,8,1,7] → 0→8 and 1→7. 0→2→4→7→9→... hmm 0→8? 0→2→4→7→9→... no edge to 8. 0→2→5→7→9→11 no. Actually 8 is reached from 6: 3→6→8. No path 0→8. So fragment 8 ineligible.

- Episode 46: derive; F9; span [33775, 33996]; prior None; definite repeat False; native truth False

> fragment 9: [9,3,7,2,9] → 3→7 and 2→9. 3→6→8→9... 3→7? no edge to 7 from 6/8/9? 3→6→8→9 no 7. So 3→7 doesn't exist? Edges reaching 7: 4→7,5→7. 4 from 2, 5 from 2. 2 from 0 or 1. So 3 cannot reach 7. Fragment 9 ineligible.

- Episode 47: derive; F10; span [33999, 34149]; prior None; definite repeat False; native truth False

> fragment 10: [10,4,8,5,11] → 4→8 and 5→11. 4→7→9... 4→7→9→11, no 8. So 4→8 no. Ineligible? 4→7, 7→9, 9→11. 8 only from 6. 4 can't reach 8. Ineligible.

- Episode 48: derive; F11; span [34152, 34245]; prior None; definite repeat False; native truth False

> fragment 11: [11,10,9,0,7] → 10→9 and 0→7. 10→11 only edge out of 10, so 10→9 no. Ineligible.

- Episode 49: conditional_recheck; F6; span [35832, 35925]; prior None; definite repeat False; native truth True

> Choose option 30.
> 
> Actually wait, option 30 id 30 was in incumbent selection last element 30!

- Episode 50: derive; F6; span [38895, 39036]; prior 43; definite repeat True; native truth True

> Let me double check eligibility of fragment 6: needs [6,3,8,9,11] → 3→8 via 3→6→8 (edges [3,6],[6,8]). 9→11 via [9,11]. Both exist. Eligible.

- Episode 52: derive; F2; span [41444, 41542]; prior 39; definite repeat True; native truth True

> Option32 fragment2: first 4->11 exists? 4->7->9->11 yes. second 5->9 exists 5->7->9 yes. Eligible.

- Episode 54: derive; F0; span [43204, 43270]; prior 37; definite repeat True; native truth True

> Path 0->7: 0->2->4->7 yes. Path 1->9: 1->2->5->7->9 yes. Eligible.

- Episode 55: derive; F2; span [43340, 43402]; prior 2; definite repeat True; native truth True

> Path 4->11: 4->7->9->11 yes. Path 5->9: 5->7->9 yes. Eligible.

- Episode 56: derive; F10; span [43448, 43619]; prior None; definite repeat False; native truth False

> first 4->8? Edges 4->7, 7->9, 9->11; no to 8. 4->...->8? 4->7->9? 9->? no to 8. So 4->8 does not exist. second 5->11: 5->7->9->11 yes. Not both. So option 34 inadmissible.

- Episode 58: mention; F2; span [51647, 51801]; prior None; definite repeat False; native truth False

> Need for fragment 2: paths 4->11 and 5->9 exist? Edges directed. From 4: 4->7->9->11 yes 4 to 11 exists (4,7),(7,9),(9,11). From 5: 5->7->9 yes. Eligible.

- Episode 59: uncertain; F10; span [51802, 51945]; prior None; definite repeat False; native truth True

> Fragment 10: first 4->8? second 5->11? Edges: 4->7->9->11, not 4->8 (4->7->9, no 8). Could 4->? no. second 5->11: 5->7->9->11 yes. First fails.

- Episode 60: derive; F10; span [53778, 54004]; prior None; definite repeat False; native truth False

> Path 4→8: 4→7→9→8? edges 7→9, 8→9 is directed 8→9, not 9→8. Hmm. 4→7, 7→9, 9→11... to reach 8: need edge into 8. Edges into 8: [6,8] only. 6→8. Into 6: [3,6]. 3→6. Into 3: none. So 8 reachable only from 6←3. So 4→8 impossible.

- Episode 61: derive; F10; span [54046, 54110]; prior None; definite repeat False; native truth False

> Second path 5→11: 5→7→9→11 exists. Both must exist; first fails.

- Episode 62: derive; F5; span [54707, 54826]; prior 23; definite repeat True; native truth True

> Directed edges: 2->4->7 exists (2->4,4->7). So first path 2->7 exists. Second path 8->11: 8->9->11 exists. So eligible.

- Episode 63: derive; F7; span [54828, 54956]; prior 24; definite repeat True; native truth True

> Option 26: fragment 7. Row 7: [7,0,9,10,11]. First path 0->9, second path 10->11. 0->2->4->7->9 exists. 10->11 exists. Eligible.

- Episode 64: derive; F1; span [54958, 55073]; prior 1; definite repeat True; native truth True

> Option 27: fragment 1. Row 1: [1,2,9,3,11]. First 2->9, second 3->11. 2->4->7->9 yes. 3->6->8->9->11 yes. Eligible.

- Episode 65: derive; F9; span [55075, 55276]; prior None; definite repeat False; native truth False

> Option 29: fragment 9. Row 9: [9,3,7,2,9]. First 3->7, second 2->9. 3->6->8->9... 3->7? 3->6->8->9->... no 7. Hmm, 3->6->8->9, no edge to 7. Actually 3->6,6->8,8->9,9->11. No 7. So 3->7 does not exist.

- Episode 66: reuse; F5; span [56511, 56665]; prior None; definite repeat False; native truth True

> But wait, need to verify fragment 5 paths fully: needs row [5,2,7,8,11]: firstFrom=2, firstTo=7, secondFrom=8, secondTo=11. 2->7 yes, 8->11 yes. Eligible.

- Episode 67: derive; F0; span [57079, 57175]; prior 0; definite repeat True; native truth True

> f0: [0,0,7,1,9] → path 0→7 and 1→9. Edges: 0→7? chain 0→2→4→7 yes. 1→9? 1→2→4→7→9 yes. eligible.

- Episode 68: derive; F1; span [57178, 57246]; prior 1; definite repeat True; native truth True

> f1: [1,2,9,3,11] → 2→9? 2→4→7→9 yes. 3→11? 3→6→8→9→11 yes. eligible.

- Episode 69: derive; F2; span [57249, 57313]; prior 2; definite repeat True; native truth True

> f2: [2,4,11,5,9] → 4→11? 4→7→9→11 yes. 5→9? 5→7→9 yes. eligible.

- Episode 70: derive; F3; span [57316, 57372]; prior None; definite repeat False; native truth True

> f3: [3,0,11,3,9] → 0→11 yes, 3→9? 3→6→8→9 yes. eligible.

- Episode 71: derive; F4; span [57375, 57441]; prior 4; definite repeat True; native truth True

> f4: [4,1,7,6,11] → 1→7? 1→2→4→7 yes. 6→11? 6→8→9→11 yes. eligible.

- Episode 72: derive; F5; span [57444, 57506]; prior 23; definite repeat True; native truth True

> f5: [5,2,7,8,11] → 2→7? 2→4→7 yes. 8→11? 8→9→11 yes. eligible.

- Episode 73: derive; F6; span [57509, 57571]; prior 19; definite repeat True; native truth True

> f6: [6,3,8,9,11] → 3→8? 3→6→8 yes. 9→11? yes (9→11). eligible.

- Episode 74: derive; F7; span [57574, 57643]; prior 24; definite repeat True; native truth True

> f7: [7,0,9,10,11] → 0→9? 0→2→4→7→9 yes. 10→11? yes (10→11). eligible.

- Episode 75: derive; F8; span [57646, 57830]; prior None; definite repeat False; native truth False

> f8: [8,0,8,1,7] → 0→8? 0→2→4→7→9→? no edge to 8 from 9. Hmm 8 reachable from 0? edges into 8: 6→8. 3→6, but 3 reachable from 0? 0→2... no path to 3. So 0→8 not reachable. Not eligible.

- Episode 76: uncertain; F9; span [57867, 57943]; prior None; definite repeat False; native truth False

> f9: [9,3,7,2,9] → 3→7? 3→6→8→9... 9→? no. Actually 3→7? no path. not needed.

- Episode 77: derive; F10; span [57946, 58086]; prior None; definite repeat False; native truth False

> f10: [10,4,8,5,11] → 4→8? 4→7→9 no to 8. Not reachable (8 only from 6, unreachable from 4). Hmm not eligible! but child 34 uses fragment 10.

- Episode 78: derive; F11; span [58089, 58131]; prior None; definite repeat False; native truth False

> f11: [11,10,9,0,7] → 10→9? 10→11 only. no.

- Episode 79: derive; F10; span [58189, 58501]; prior None; definite repeat False; native truth False

> Eligibility: f6 eligible, f0 eligible, f2 eligible, f4 eligible, f10 - need check 4→8 path and 5→11 path. 5→11: 5→7→9→11 yes. 4→8: edges: 4→7, 7→9, 9→11; 8 has incoming from 6. Can we reach 6? from 4? no. So 4→8 not a path. So f10 ineligible → expand 34 would be a pruning step. But better choose eligible child.

- Episode 80: derive; F6; span [61156, 61308]; prior 19; definite repeat True; native truth True

> Choose option 30 (fragment 6, eligible). Let's verify f6 eligible: needs [6,3,8,9,11]: 3→8 path: 3→6→8 yes. 9→11: edge [9,11] yes. Both exist. Eligible.

- Episode 81: derive; F0; span [62085, 62386]; prior 37; definite repeat True; native truth True

> fragment0: [0,0,7,1,9] => first path 0->7, second path 1->9. Check directed paths in edges. Edges directed from first to second. 0->2->4->7 exists? 0->2 edge yes, 2->4 yes, 4->7 yes. So first exists. 1->2->5->7->9? 1->2 edge, 2->5,5->7,7->9 yes. Or 1->2->4->7->9. So second exists. fragment0 eligible.

- Episode 82: derive; F2; span [62388, 62477]; prior 2; definite repeat True; native truth True

> fragment2: [2,4,11,5,9] first 4->11, second 5->9. 4->7->9->11 yes. 5->7->9 yes. eligible.

- Episode 83: derive; F4; span [62479, 62586]; prior 4; definite repeat True; native truth True

> fragment4: [4,1,7,6,11] first 1->7 yes (1->2->4->7 or 1->2->5->7); second 6->11? 6->8->9->11 yes. eligible.

- Episode 84: derive; F10; span [62588, 62804]; prior None; definite repeat False; native truth False

> fragment10: [10,4,8,5,11] first 4->8? edges 4->7->9? no 4->8? no edge 4->7,7->9,9->11; 8 not reachable from 4? 4->7->9->11, no 8. 4->? 2->4 but reverse. So no. second 5->11? 5->7->9->11 yes. But both required, fails.

- Episode 85: derive; F4; span [70667, 70783]; prior 4; definite repeat True; native truth True

> id33 fragment4 needs [4,1,7,6,11]: 1->7 and 6->11. Edges: 1->2->4->7 or 1->2->5->7. 6->8->9->11. Yes. Both eligible.

- Episode 86: reuse; F4; span [75042, 75114]; prior None; definite repeat False; native truth True

> Check eligibility: fragment4 needs paths 1->7 and 6->11 both exist. Yes.

- Episode 87: derive; F0; span [75574, 75782]; prior None; definite repeat False; native truth True

> Fragment 0: needs [0,0,7,1,9] => first path 0->7, second 1->9. Are both directed paths in source edges? Need path from 0 to 7: 0->2->4->7 or 0->2->5->7 yes. 1->9: 1->2->4->7->9 or 1->2->5->7->9 yes. Eligible.

- Episode 88: derive; F2; span [75784, 75877]; prior 2; definite repeat True; native truth True

> Fragment 2: [2,4,11,5,9] => 4->11, 5->9. 4->11: 4->7->9->11 yes. 5->9: 5->7->9 yes. Eligible.

- Episode 89: derive; F10; span [75879, 76074]; prior None; definite repeat False; native truth True

> Fragment 10: [10,4,8,5,11] => 4->8, 5->11. 4->8? edges from 4 only to7, then 7->9, 9->11, no 8. Could 4->7->9->? 9->11 only. No edge to 8 except 6->8. So 4->8 absent. Thus fragment 10 ineligible.

- Episode 91: reuse; F0; span [83788, 83826]; prior None; definite repeat False; native truth False

> So option 31 (fragment 0) is eligible.

- Episode 94: derive; F10; span [85306, 85419]; prior None; definite repeat False; native truth False

> Fragment ID 10 row: firstFrom=4, firstTo=8; secondFrom=5, secondTo=11. Need paths 4->8 and 5->11 in source edges.

- Episode 95: derive; F10; span [85513, 85690]; prior None; definite repeat False; native truth False

> Path 4->8: edges 4->7, 7->9, 9->11? Need to 8. 4->7, 7->9, 9->11; from 11 no to 8. Maybe 4->7->? 7->9, 9->11, no 8. 8 is only edge 6->8, from 6? 4->7 no. So 4->8 does NOT exist.

- Episode 96: derive; F10; span [85813, 85856]; prior None; definite repeat False; native truth False

> Thus eligibility fails. Child inadmissible.

- Episode 97: derive; F7; span [86334, 86527]; prior 24; definite repeat True; native truth True

> - fragmentId 7: [7,0,9,10,11] → firstFrom=0, firstTo=9, secondFrom=10, secondTo=11. Path 0→9: edges? 0→2, 2→4, 4→7, 7→9 yes 0→2→4→7→9 exists. 10→11: edge [10,11] exists. So fragment 7 eligible.

- Episode 98: derive; F1; span [86528, 86632]; prior 1; definite repeat True; native truth True

> - fragmentId 1: [1,2,9,3,11] → first 2→9, second 3→11. 2→9: 2→4→7→9 yes. 3→11: 3→6→8→9→11 yes. Eligible.

- Episode 99: derive; F9; span [86633, 86854]; prior None; definite repeat False; native truth False

> - fragmentId 9: [9,3,7,2,9] → first 3→7, second 2→9. 3→7: 3→6→8→9... 9→11 no 7. Hmm 3→6→8→9, no edge to 7. Any path 3→7? edges from 3: 3→6; from 6:6→8; from 8:8→9; from 9:9→11. No 7. So no path 3→7. Fragment 9 ineligible.

- Episode 100: mention; FNone; span [86856, 86901]; prior None; definite repeat False; native truth False

> So options 26 and 27 eligible; 29 ineligible.

Rejected labels retained:
[{"annotation":{"claim":"Fragment 0 eligible: 0→7 and 1→9 both exist.","explanation":"Rederives fragment 0 eligibility from the same edges in a later call context.","fragment":0,"kind":"derive","occurrence":0,"paths":[[0,7],[1,9]],"premiseEdges":[[0,2],[2,4],[4,7],[1,2],[2,4],[4,7],[7,9]],"prior":0,"quote":"31 fragment0: first 0->7 exists yes 0-2-4-7 or 0-2-5-7. second 1->9 yes 1->2->4->7->9. Eligible.","ready":true},"chunkFirstCall":6,"failure":"different conclusion/premise context","index":14},{"annotation":{"claim":"Fragment 4 eligible: 1→7 via [1,2],[2,4],[4,7] and 6→11 via [6,8],[8,9],[9,11].","explanation":"Repeat fragment 4 eligibility derivation from same edge set.","fragment":4,"kind":"derive","occurrence":0,"paths":[[1,7],[6,11]],"premiseEdges":[[1,2],[2,4],[4,7],[6,8],[8,9],[9,11]],"prior":3,"quote":"Option33 fragment4: first 1->7 exists 1->2->4->7 yes. second 6->11 exists 6->8->9->11 yes. Eligible.","ready":true},"chunkFirstCall":6,"failure":"different conclusion/premise context","index":16},{"annotation":{"claim":"Both fragments 0 and 2 have their path requirements met.","explanation":"Explicitly summarizes previously established results that both fragments are eligible without reconstructing edge premises.","fragment":null,"kind":"reuse","occurrence":0,"paths":[[0,7],[1,9],[4,11],[5,9]],"premiseEdges":[],"prior":null,"quote":"Option 31 fragment 0 paths both exist as above. Option 32 fragment 2 paths exist. Both eligible.","ready":true},"chunkFirstCall":8,"failure":"quote not present verbatim","index":3},{"annotation":{"claim":"Fragments 0, 2, 10 to be checked.","explanation":"This is just a mention of candidate fragments, not a path inference itself.","fragment":null,"kind":"mention","occurrence":0,"paths":[],"premiseEdges":[],"prior":null,"quote":"Need verify for fragments 0,2,10.","ready":null},"chunkFirstCall":14,"failure":"out of chronological order","index":3},{"annotation":{"claim":"Fragment 0 both paths exist, eligible. 0->7 via 0->2->4->7, and 1->9 via 1->2->4->7->9.","explanation":"This is a second derivation of fragment 0 eligibility, but with a different witness edge chain than the first one, so it is a new alternative witness rather than a duplicate.","fragment":0,"kind":"derive","occurrence":0,"paths":[[0,7],[1,9]],"premiseEdges":[[0,2],[2,4],[4,7],[1,2],[7,9]],"prior":null,"quote":"Fragment 0: needs row [0,0,7,1,9] → firstFrom=0, firstTo=7, secondFrom=1, secondTo=9. Edges: [0,2],[2,4],[4,7] gives path 0→2→4→7. Second: 1→2→4→5? Wait need 1→9. Edges from 1: [1,2]. 2→4,4→7,7→9. So 1→2→4→7→9 exists. Yes both paths exist. Eligible.","ready":true},"chunkFirstCall":14,"failure":"out of chronological order","index":5},{"annotation":{"claim":"Fragment 10 ineligible because 4->8 is absent.","explanation":"This is a second negative eligibility derivation for fragment 10, with a slightly different edge list considered; retained as a separate branch episode.","fragment":10,"kind":"derive","occurrence":0,"paths":[[4,8],[5,11]],"premiseEdges":[[4,7],[7,9],[9,11],[8,9]],"prior":null,"quote":"Fragment 10: needs [10,4,8,5,11]. First path 4→8: edges from 4: [4,7]. 7→9, 9→11, ... 8? Hmm. Let's find 4→8. Edges: [4,7],[7,9],[9,11],[8,9]. Can we reach 8 from 4? 4→7→9... 9→11 only. No edge to 8. So 4→8 does not exist. Not eligible.","ready":false},"chunkFirstCall":14,"failure":"out of chronological order","index":6}]

## paid/branch-search-6-fresh-0

Text SHA `1c479df99fa610ddb73829998e0a221ad3deb2e2b70a02df84804859cff758f5`; annotation failure `None`.

- Episode 0: derive; F0; span [913, 1066]; prior None; definite repeat False; native truth True

> Fragment 0: need [0,0,7,1,9] → path 0→7 and path 1→9.
> - 0→7: 0→2→4→7. Yes (edges 0-2,2-4,4-7).
> - 1→9: 1→2→4→7→9 or 1→2→5→7→9. Yes (1→2,2→4,4→7,7→9). Yes.

- Episode 1: derive; F2; span [1068, 1165]; prior None; definite repeat False; native truth True

> Fragment 2: need [2,4,11,5,9] → path 4→11 and path 5→9.
> - 4→11: 4→7→9→11. Yes.
> - 5→9: 5→7→9. Yes.

- Episode 2: derive; F4; span [1167, 1266]; prior None; definite repeat False; native truth True

> Fragment 4: need [4,1,7,6,11] → path 1→7 and path 6→11.
> - 1→7: 1→2→4→7. Yes.
> - 6→11: 6→8→9→11. Yes.

- Episode 3: derive; F6; span [1268, 1361]; prior None; definite repeat False; native truth True

> Fragment 6: need [6,3,8,9,11] → path 3→8 and path 9→11.
> - 3→8: 3→6→8. Yes.
> - 9→11: 9→11. Yes.

- Episode 4: derive; F8; span [2840, 3069]; prior None; definite repeat False; native truth False

> Path 0→8? Let's see all edges: [0,2],[1,2],[2,4],[2,5],[4,7],[5,7],[3,6],[6,8],[7,9],[8,9],[9,11],[10,11]. To reach 8, must come from 6. To reach 6, must come from 3. 3 has no incoming edges. So from 0, can't reach 8. Ineligible.

- Episode 5: derive; F4; span [6927, 7161]; prior 2; definite repeat True; native truth True

> But wait—I should double check eligibility of fragment 4 more carefully. Fragment 4 need: [4,1,7,6,11] → path 1→7 and path 6→11.
> 
> Path 1→7: 1→2→4→7 (edges 1-2, 2-4, 4-7). Yes.
> Path 6→11: 6→8→9→11 (edges 6-8, 8-9, 9-11). Yes. Eligible.

- Episode 6: derive; F6; span [7163, 7288]; prior 3; definite repeat True; native truth True

> Option 3 fragment 6: need [6,3,8,9,11] → path 3→8 and 9→11.
> 3→8: 3→6→8 (edges 3-6, 6-8). Yes.
> 9→11: edge 9-11. Yes. Eligible.

- Episode 7: derive; F0; span [9251, 9336]; prior 0; definite repeat True; native truth True

> Option 0: need [0,0,7,1,9]. path 0→7: 0→2→4→7 yes. path 1→9: 1→2→4→7→9 yes. Eligible.

- Episode 9: derive; F1; span [11866, 11969]; prior None; definite repeat False; native truth False

> Fragment 1 need [1,2,9,3,11]: paths from 1 to2 exists edge [1,2] yes. 9 to11 edge [9,11] yes. eligible.

- Episode 10: derive; F3; span [11971, 12092]; prior None; definite repeat False; native truth True

> Fragment 3 need [3,0,11,3,9]: paths 0->11? edges include 0->2->4->7->9->11 etc yes. 3->9? edges 3->6->8->9 yes. eligible.

- Episode 11: derive; F5; span [12094, 12183]; prior None; definite repeat False; native truth True

> Fragment5 need [5,2,7,8,11]: 2->7? 2->4->7 or 2->5->7 yes. 8->11? 8->9->11 yes. eligible.

- Episode 12: derive; F7; span [12185, 12249]; prior None; definite repeat False; native truth True

> Fragment7 need [0,9,10,11]: 0->9 yes. 10->11 edge yes. eligible.

- Episode 13: derive; F9; span [12251, 12427]; prior None; definite repeat False; native truth False

> Fragment9 need [3,7,2,9]: 3->7? edges 3->6->8->9, but to 7? 3->6->8->9 then? 9->11 only, no 7. Maybe 3->6->8->9 no. There is no edge to 7 from 8/9. So 3->7 path does NOT exist.

- Episode 14: derive; F2; span [16049, 16096]; prior None; definite repeat False; native truth False

> Edges include 4->7->9->11 so 4->11 positive yes

- Episode 15: derive; F2; span [16098, 16109]; prior None; definite repeat False; native truth False

> 5->7->9 yes

- Episode 16: derive; F2; span [16111, 16137]; prior None; definite repeat False; native truth True

> Eligible.
> 
> Fragment 4 need

- Episode 17: derive; F4; span [16152, 16196]; prior None; definite repeat False; native truth False

> paths 1->7 (1->2->5->7 or 1->2->4->7) exists

- Episode 18: derive; F4; span [16198, 16224]; prior None; definite repeat False; native truth False

> 6->11 (6->8->9->11) exists

- Episode 19: derive; F4; span [16226, 16252]; prior None; definite repeat False; native truth True

> Eligible.
> 
> Fragment 6 need

- Episode 20: derive; F6; span [16267, 16288]; prior None; definite repeat False; native truth False

> 3->8 (3->6->8) exists

- Episode 21: derive; F6; span [16290, 16302]; prior None; definite repeat False; native truth False

> 9->11 exists

- Episode 22: derive; F6; span [16304, 16330]; prior None; definite repeat False; native truth True

> Eligible.
> 
> Fragment 0 need

- Episode 23: derive; F0; span [16344, 16378]; prior None; definite repeat False; native truth True

> 0->7 exists; 1->9 exists. Eligible

- Episode 24: uncertain; F10; span [16413, 16550]; prior None; definite repeat False; native truth False

> 4->8? Edges: 4->7->9->? no to8. 4->7->9->? 11 no 8. There is no edge 7->8 or 9->8, only 6->8. So 4->8 absent. Thus fragment 10 ineligible

- Episode 25: derive; F3; span [22510, 22610]; prior 10; definite repeat True; native truth True

> fragment3: paths 0->11 and 3->9. Source edges: 0->2->4->7->9->11 yes 0->11. 3->6->8->9 yes. eligible

- Episode 26: derive; F5; span [22613, 22671]; prior None; definite repeat False; native truth True

> frag5: 2->7 and 8->11. 2->4->7 yes; 8->9->11 yes. eligible

- Episode 27: derive; F7; span [22674, 22744]; prior 12; definite repeat True; native truth True

> frag7: 0->9 and 10->11. 0->2->4->7->9 yes; 10->11 direct yes. eligible

- Episode 28: derive; F1; span [22747, 22814]; prior None; definite repeat False; native truth True

> frag1: 2->9 and 3->11. 2->4->7->9 yes; 3->6->8->9->11 yes. eligible

- Episode 29: uncertain; F11; span [22817, 22914]; prior None; definite repeat False; native truth False

> frag11: 10->9 and 0->7. 10->9? edges 10->11, no path 10 to9 (only outgoing 10->11). So ineligible

- Episode 30: derive; F4; span [26660, 26768]; prior 19; definite repeat True; native truth True

> 20 fragment 4: needs 1->7,6->11. Evidence path [1,7] rule id48; path [6,11] rule id53. Both exist. Eligible.

- Episode 31: derive; F6; span [26769, 26860]; prior 22; definite repeat True; native truth True

> 21 fragment 6: needs 3->8,9->11. Path [3,8] id43; [9,11] id34 (source edge also). Eligible.

- Episode 32: derive; F0; span [26861, 26931]; prior 23; definite repeat True; native truth True

> 22 fragment 0: needs 0->7,1->9. Path [0,7] id47; [1,9] id57. Eligible.

- Episode 33: derive; F2; span [26932, 27004]; prior 16; definite repeat True; native truth True

> 23 fragment 2: needs 4->11,5->9. Path [4,11] id50; [5,9] id42. Eligible.

- Episode 34: derive; F8; span [27114, 27352]; prior None; definite repeat False; native truth False

> Does 0->8 exist? Source edges: 0->2, 3->6, etc. There is no edge into 8 except 6->8. Path 0->8? Could go 0->2->4->7->9? 9->11 no to 8. 0->2->5->7->9 no. 0->2->4->7? 7 no to 8. 0->? No rule path [0,8] in evidence. So fragment 8 ineligible.

- Episode 35: reuse; F2; span [30074, 30279]; prior None; definite repeat False; native truth True

> Need ensure eligibility: fragment 2 both paths 4->11 and 5->9 exist. Evidence rule [50,"rule","path",[4,11],4,[41,10]] and [42,"rule","path",[5,9],4,[29,8]]; source paths [41] 4->9, [42] 5->9. So eligible.

- Episode 36: derive; F5; span [31963, 32111]; prior 26; definite repeat True; native truth True

> need[5]: [5,2,7,8,11] → paths 2→7 and 8→11. Path 2→7: edges [2,4],[4,7] yes (derivation 40). 8→11: edges [8,9],[9,11] yes (derivation 46). Eligible.

- Episode 37: derive; F7; span [32114, 32218]; prior None; definite repeat False; native truth True

> need[7]: [7,0,9,10,11] → 0→9 and 10→11. 0→9: path exists (56, [0,9]). 10→11: edge [10,11] yes. Eligible.

- Episode 38: derive; F1; span [32221, 32343]; prior None; definite repeat False; native truth False

> need[1]: [1,2,9,3,11] → paths 1→9 and 3→11. 1→9: 38,48,57 yes. 3→11: [3,6],[6,8],[8,9],[9,11] derivation 59 yes. Eligible.

- Episode 39: derive; F3; span [32346, 32464]; prior None; definite repeat False; native truth True

> need[3]: [3,0,11,3,9] → 0→11 and 3→9. 0→11 exists (derivation 62). 3→9: [3,6],[6,8],[8,9] derivation 52 yes. Eligible.

- Episode 40: derive; F9; span [32503, 32763]; prior None; definite repeat False; native truth False

> Path 3→7: edges [3,6],[6,8],[7,9]? 3→6→8, 8→? edges from 8: [8,9]. So 3→8 exists (43), but 3→7? Edge 6→? [6,8]. No edge to 7 from 6 or 8. So 3→7 path? Let's see edges: [3,6],[6,8],[8,9]. No 7 in that. So path 3→7 does not exist. Hence fragment 9 is INELIGIBLE.

- Episode 41: reuse; F3; span [42777, 42985]; prior None; definite repeat False; native truth True

> Fragment 3: need F3 = [3,0,11,3,9]. Paths: 0→11 via derivations 56 ([0,9]) + 10 ([9,11]) = 62 ([0,11]). 3→9 via 30 ([3,6]) + 31 ([6,8])? Actually 43 ([3,8]) then 33 ([8,9]) = 52 ([3,9]). Yes both exist. Good.

- Episode 43: derive; F6; span [44695, 44820]; prior 3; definite repeat True; native truth True

> Child option id 30, fragment 6: need [3,8,9,11]. Path 3->8: 3->6->8 exists. Path 9->11: 9->11 exists. Both exist => eligible.

- Episode 44: derive; F0; span [44822, 44921]; prior 0; definite repeat True; native truth True

> Child id31 fragment0: [0,7,1,9]. Path 0->7: 0->2->4->7 yes. Path 1->9: 1->2->4->7->9 yes. Eligible.

- Episode 45: derive; F2; span [44923, 45019]; prior 1; definite repeat True; native truth True

> Child id32 fragment2: [4,11,5,9]. Path 4->11: 4->7->9->11 yes. Path 5->9: 5->7->9 yes. Eligible.

- Episode 46: derive; F4; span [45021, 45120]; prior 2; definite repeat True; native truth True

> Child id33 fragment4: [1,7,6,11]. Path 1->7: 1->2->4->7 yes. Path 6->11: 6->8->9->11 yes. Eligible.

- Episode 47: derive; F10; span [45122, 45312]; prior None; definite repeat False; native truth False

> Child id34 fragment10: [4,8,5,11]. Path 4->8: need 4->8. Edges: 4->7->9, 7->9, 9->11; 4->7->... no 4->8. There's 3->6->8 but from 4 to 8? 4->7->9->... no. So 4->8 does not exist. Ineligible.

- Episode 48: derive; F4; span [50411, 50606]; prior 46; definite repeat True; native truth True

> Wait, but need to double-check eligibility for id33's fragment 4: paths 1->7 and 6->11. 1->2->4->7: edges 1->2 yes, 2->4 yes, 4->7 yes. 6->8->9->11: 6->8 yes, 8->9 yes, 9->11 yes. Eligible. Good.

- Episode 49: derive; F6; span [51267, 51429]; prior 43; definite repeat True; native truth True

> Need for fragment 6: need row id6: [6,3,8,9,11] => paths 3->8 and 9->11. Edges: 3->6->8 path exists (edges [3,6],[6,8]); 9->11 exists edge. So fragment6 eligible.

- Episode 50: derive; F0; span [51431, 51524]; prior 44; definite repeat True; native truth True

> Fragment0: needs [0,0,7,1,9] => 0->7 path? 0->2->4->7 yes. 1->9? 1->2->4->7->9 yes. eligible.

- Episode 51: derive; F2; span [51526, 51611]; prior 45; definite repeat True; native truth True

> Fragment2: needs [2,4,11,5,9] => 4->11? 4->7->9->11 yes. 5->9? 5->7->9 yes. eligible.

- Episode 52: derive; F10; span [51613, 51827]; prior 47; definite repeat False; native truth False

> Fragment10: needs [10,4,8,5,11] => 4->8? edges 4->7->9? and 6->8 but 4 to8? Let's see directed edges: [4,7],[7,9],[8,9]. No path 4->8 (7->9, 8->9 not to 8). Maybe 4->7->9 ... no edge to 8. So fragment10 ineligible.

- Episode 53: derive; F0; span [55550, 55646]; prior 23; definite repeat True; native truth True

> fragment 0 need [0,0,7,1,9]: paths 0->7 and 1->9? Both exist? yes path 0->7 (node47), 1->9 (57).

- Episode 54: uncertain; F1; span [55647, 55709]; prior None; definite repeat False; native truth False

> fragment1 need [1,2,9,3,11]: paths 2->9? and 3->11? yes maybe.

- Episode 55: derive; F2; span [55710, 55911]; prior 16; definite repeat True; native truth True

> fragment2 need [2,4,11,5,9]: paths 4->11 and 5->9. Need both positive-length directed paths exist in source edges. From evidence path rules include 4->11 node50, 5->9 node42 yes. So fragment2 eligible.

- Episode 56: derive; F6; span [55913, 56000]; prior 22; definite repeat True; native truth True

> fragment6 need [6,3,8,9,11]: paths 3->8 (node43), 9->11 (node34). Both exist. Eligible.

- Episode 57: derive; F10; span [56002, 56243]; prior None; definite repeat False; native truth False

> fragment10 need [10,4,8,5,11]: paths 4->8? Need source edges: edges [4,7],[5,7],[3,6],[6,8]... Path 4->8? 4->7->9? 9->? 8? no edge to 8? Actually edges: 4->7, 7->9, 9->11, 8->9. To 8 from 4? 4->7->9 no 8, 4->... no. Path 4->8 does not exist?

- Episode 58: derive; F10; span [56357, 56457]; prior None; definite repeat False; native truth True

> So fragment10 ineligible. Need check derivation evidence path [4,8]? none. So option34 inadmissible.

- Episode 61: mention; F2; span [65254, 65412]; prior None; definite repeat False; native truth False

> Option id32 fragment2 has cost12 risk6 value total 266 prefixTotals, seedSuffixTotals same? It says costs 55? Wait prefixTotals cost55 depth7 risk38 value266.

- Episode 62: reuse; F2; span [66504, 66561]; prior None; definite repeat False; native truth False

> Option 32 eligible but prefixTotals maybe over riskLimit.

Rejected labels retained:
[{"annotation":{"claim":"Re-derivation of fragment 2 eligibility: 4→11 via 4→7→9→11 and 5→9 via 5→7→9.","explanation":"Same conclusion and same edge chains as the earlier fragment 2 derivation.","fragment":2,"kind":"derive","occurrence":0,"paths":[[4,11],[5,9]],"premiseEdges":[[4,7],[7,9],[9,11],[5,7],[7,9]],"prior":1,"quote":"Option 1 fragment 2: [2,4,11,5,9]: 4→11: 4→7→9→11 yes. 5→9: 5→7→9 yes. Eligible.","ready":true},"chunkFirstCall":0,"failure":"different conclusion/premise context","index":8},{"annotation":{"claim":"Fragment 3 is marked ready per derivation node 67.","explanation":"Cites an existing ready node to support F3 readiness.","fragment":3,"kind":"reuse","occurrence":0,"paths":[],"premiseEdges":[],"prior":null,"quote":"Also fragment 3 appears in derivation nodes 67 \"ready\",[3],5,[15,62,52]. Yes ready.","ready":true},"chunkFirstCall":4,"failure":"out of chronological order","index":12},{"annotation":{"claim":"Fragment 2 is eligible because 4->11 holds via 4->7->9->11 and 5->9 holds via 5->7->9.","explanation":"Same conclusion as the earlier fragment 2 eligibility derivation but with explicit edge chains 4->7->9->11 and 5->7->9; distinct support context and explicit chain make it a new derivation rather than a replay.","fragment":2,"kind":"derive","occurrence":0,"paths":[[4,11],[5,9]],"premiseEdges":[[4,7],[7,9],[9,11],[5,7],[7,9]],"prior":2,"quote":"Fragments correspond? needs rows by fragmentId. Need fragment 2: row [2,4,11,5,9]? columns fragmentId, firstFrom, firstTo, secondFrom, secondTo. So fragment 2 requires path from 4 to11 and from5 to9? Wait row [2,4,11,5,9] => firstFrom=4 firstTo=11 secondFrom=5 secondTo=9. Need both positive-length directed paths exist in source edges. Source edges: 2->4,2->5,4->7,5->7,7->9,8->9,9->11,10->11, etc. Path 4->11: 4->7->9->11 yes. Path 5->9: 5->7->9 yes. So fragment2 eligible.","ready":true},"chunkFirstCall":8,"failure":"different conclusion/premise context","index":6},{"annotation":{"claim":"Fragment 10 is not eligible because required path 4->8 cannot be reached from 4 under the listed source edges.","explanation":"Re-derives fragment 10 ineligibility with explicit edges; same conclusion as prior negative derivation but with a fuller listed edge set, treated as new derivation.","fragment":10,"kind":"derive","occurrence":0,"paths":[[4,8],[5,11]],"premiseEdges":[[4,7],[7,9],[9,11],[8,9]],"prior":5,"quote":"Fragment10: row [10,4,8,5,11] => paths 4->8 and 5->11. Source edges: 4->7,5->7,7->9,8->9,9->11. Is there path 4->8? From 4 to? edges: 4->7->9->11; no 8. 8->9, but cannot reach 8 from4. So not eligible? Need both positive paths. Fragment10 first 4->8 doesn't exist. Thus option id34 ineligible.","ready":false},"chunkFirstCall":8,"failure":"different conclusion/premise context","index":7}]

## paid/branch-search-6-fresh-1

Text SHA `68f9a9cca0e079dda7294b3cd4dd2b80bb4c9595c08cfe47418e0b3f036e8201`; annotation failure `None`.

- Episode 0: derive; F2; span [675, 778]; prior None; definite repeat False; native truth True

> Eligible.
> 
> Fragment2 need [2,4,11,5,9]: path 4->11? edges 4->7->9->11 yes; 5->9? 5->7->9 yes. Eligible.

- Episode 1: derive; F4; span [780, 863]; prior None; definite repeat False; native truth True

> Fragment4 need [4,1,7,6,11]: path 1->7 yes; 6->11? edges 6->8->9->11 yes. Eligible.

- Episode 2: derive; F6; span [865, 944]; prior None; definite repeat False; native truth True

> Fragment6 need [6,3,8,9,11]: path 3->8? edges 3->6->8 yes; 9->11 yes. Eligible.

- Episode 3: uncertain; F8; span [1095, 1141]; prior None; definite repeat False; native truth False

> So 0->8 likely missing. Fragment 8 ineligible.

- Episode 4: derive; F1; span [3476, 3596]; prior None; definite repeat False; native truth True

> option id5 fragment 1: paths 2->9 and 3->11. 2->9? 2->4->7->9 yes (2->4,4->7,7->9). 3->11? 3->6->8->9->11 yes. Eligible.

- Episode 5: derive; F3; span [3598, 3723]; prior None; definite repeat False; native truth True

> id6 fragment3: paths 0->11 and 3->9. 0->11? 0->2->5->7->9->11? yes 0->2,2->5,5->7,7->9,9->11. 3->9? 3->6->8->9 yes. Eligible.

- Episode 6: derive; F5; span [3725, 3822]; prior None; definite repeat False; native truth True

> id7 fragment5: paths 2->7 and 8->11. 2->7? 2->4->7 or 2->5->7 yes. 8->11? 8->9->11 yes. Eligible.

- Episode 7: derive; F7; span [3824, 3908]; prior None; definite repeat False; native truth True

> id8 fragment7: paths 0->9 and 10->11. 0->9? 0->2->4->7->9 yes. 10->11 yes. Eligible.

- Episode 8: derive; F9; span [3910, 4089]; prior None; definite repeat False; native truth False

> id9 fragment9: paths 3->7 and 2->9. 3->7? 3->6->8->9? 9 can't to 7 (directed 7->9 not 9->7). Any other from 3: 3->6->8->9, no 7. So 3->7 does NOT exist. Thus fragment9 ineligible.

- Episode 9: derive; F2; span [10126, 10190]; prior None; definite repeat False; native truth True

> Directed path 4→11? 4→7→9→11 yes. 5→9? 5→7→9 yes. So both exist.

- Episode 10: derive; F2; span [10578, 10674]; prior 9; definite repeat True; native truth True

> fragment 2 requires paths 4 to 11 and 5 to 9. Source edges have 4→7→9→11 and 5→7→9. So eligible.

- Episode 13: derive; F0; span [13364, 13458]; prior None; definite repeat False; native truth True

> fragment 0: [0,0,7,1,9] means 0→7 exists 0→2→4→7 or via 5; 1→9 exists 1→2→4→7→9 etc. Both yes.

- Episode 14: derive; F10; span [13459, 13679]; prior None; definite repeat False; native truth True

> fragment 10: [10,4,8,5,11] means 4→8? Source edges 4→7, 7→9, 9→11, no 8. Is there 4→? 4→7→9→11; no 8. 5→11 exists 5→7→9→11. But 4→8 does not exist because 7 cannot go to 8 (edge 6→8, 8→9 only). So fragment 10 ineligible.

- Episode 16: derive; F3; span [16941, 17076]; prior None; definite repeat False; native truth True

> Check fragment 3: first 0->11 exists? Yes 0->2->4->7->9->11 or 0->2->5->7->9->11. second 3->9? 3->6->8->9 yes. Both exist. So eligible.

- Episode 17: derive; F5; span [17078, 17163]; prior None; definite repeat False; native truth True

> Fragment 5: first 2->7: 2->4->7 or 2->5->7 yes. second 8->11: 8->9->11 yes. Eligible.

- Episode 18: derive; F7; span [17165, 17249]; prior 7; definite repeat True; native truth True

> Fragment 7: first 0->9: 0->2->4->7->9 yes. second 10->11: edge 10->11 yes. Eligible.

- Episode 19: derive; F1; span [17251, 17348]; prior 4; definite repeat True; native truth True

> Fragment 1: first 2->9: 2->4->7->9 or 2->5->7->9 yes. second 3->11: 3->6->8->9->11 yes. Eligible.

- Episode 20: derive; F11; span [17350, 17517]; prior None; definite repeat False; native truth True

> Fragment 11: first 10->9: Is there path 10 to 9? Edge 10->11, then 11? no outgoing from 11. No 10->9. So ineligible. second 0->7 exists. But both required; ineligible.

- Episode 21: reuse; F5; span [19893, 19945]; prior None; definite repeat False; native truth True

> id16 fragment5: F5 needs 2->7 and 8->11. Both exist.

- Episode 22: derive; F4; span [21131, 21165]; prior None; definite repeat False; native truth False

> path 1->7? From 1: 1->2->4->7 yes.

- Episode 23: derive; F4; span [21166, 21202]; prior None; definite repeat False; native truth False

> path 6->11? From 6: 6->8->9->11 yes.

- Episode 25: derive; F6; span [21263, 21286]; prior None; definite repeat False; native truth False

> path 3->8? 3->6->8 yes.

- Episode 26: derive; F6; span [21287, 21319]; prior None; definite repeat False; native truth False

> path 9->11? 9->11 yes. Eligible.

- Episode 28: derive; F0; span [21355, 21381]; prior None; definite repeat False; native truth False

> path 0->7? 0->2->4->7 yes.

- Episode 29: derive; F0; span [21382, 21411]; prior None; definite repeat False; native truth False

> path 1->9? 1->2->4->7->9 yes.

- Episode 31: derive; F2; span [21458, 21486]; prior None; definite repeat False; native truth False

> path 4->11? 4->7->9->11 yes.

- Episode 32: derive; F2; span [21487, 21520]; prior None; definite repeat False; native truth False

> path 5->9? 5->7->9 yes. Eligible.

- Episode 34: derive; F8; span [21648, 21843]; prior None; definite repeat False; native truth False

> Path from 0 to 8? Edges: 0->2, 2->4/5, 4->7, 5->7, 7->9, 8->9. No edge into 8 except from 6 (6->8) and from... 3->6->8. So 0->...->8? 0->2->...->7->9 no 8. So no path 0->8. Fragment 8 ineligible.

- Episode 35: derive; F8; span [21845, 21975]; prior None; definite repeat False; native truth False

> Wait, need [8,0,8,1,7]: firstFrom 0 firstTo 8, secondFrom 1 secondTo 7. Path 0->8 doesn't exist. So fragment 8 (id 24) ineligible.

- Episode 36: reuse; F6; span [23632, 23810]; prior None; definite repeat False; native truth True

> path 3->8 via edges 3->6->8 (derivation node 43 "path",[3,8],4,[30,7]). path 9->11 via edge 9->11 (node 34). And node 55 ready [6] = [18,43,34]. So fragment 6 is ready, eligible.

- Episode 37: derive; F5; span [24371, 24497]; prior 17; definite repeat True; native truth True

> Fragment 5 has firstFrom=2 firstTo=7, secondFrom=8 secondTo=11. Source edges include path 2->4->7 yes; 8->9->11 yes. Eligible.

- Episode 38: derive; F7; span [24626, 24759]; prior 7; definite repeat True; native truth True

> id26 fragment7 need [7,0,9,10,11]: first 0->9 exists via 0->2->4->7->9 or 0->2->5->7->9; second 10->11 exists edge [10,11]. Eligible.

- Episode 39: derive; F1; span [24789, 24914]; prior 4; definite repeat True; native truth True

> id27 fragment1 need [1,2,9,3,11]: first 2->9? edges 2->4->7->9 or 2->5->7->9 yes. second 3->11? 3->6->8->9->11 yes. Eligible.

- Episode 40: derive; F3; span [24930, 25024]; prior None; definite repeat False; native truth True

> id28 fragment3 need [3,0,11,3,9]: first 0->11 exists; second 3->9 exists 3->6->8->9. Eligible.

- Episode 42: reuse; F3; span [27456, 27519]; prior None; definite repeat False; native truth True

> Need ensure fragment 3 eligible. Yes. Option id 28, fragment 3.

- Episode 43: derive; F0; span [28131, 28233]; prior None; definite repeat False; native truth True

> - fragment 0: [0,7,1,9] → path 0→7 and 1→9. Both exist? 0→7 path yes (47/56 derivation). 1→9 yes (57).

- Episode 44: derive; F2; span [28234, 28294]; prior None; definite repeat False; native truth True

> - fragment 2: [4,11,5,9] → path 4→11 (50) and 5→9 (42). Yes.

- Episode 45: derive; F4; span [28295, 28355]; prior None; definite repeat False; native truth True

> - fragment 4: [1,7,6,11] → path 1→7 (48) and 6→11 (53). Yes.

- Episode 46: derive; F6; span [28356, 28416]; prior None; definite repeat False; native truth True

> - fragment 6: [3,8,9,11] → path 3→8 (43) and 9→11 (34). Yes.

- Episode 47: derive; F10; span [28417, 28541]; prior None; definite repeat False; native truth False

> - fragment 10: [4,8,5,11] → path 4→8? Edges: 4→7, 7→9... 4→8 not present. Path 4→8 doesn't exist. So fragment 10 ineligible.

- Episode 48: derive; F10; span [28543, 28694]; prior None; definite repeat False; native truth False

> Actually need to check paths: from 4 to 8? edges: 4→7, 5→7, 7→9, etc. No 8 reachable from 4 except... 4→7→9? 9→11. 8→9. So 4 can't reach 8. Ineligible.

- Episode 50: derive; F4; span [31569, 31773]; prior None; definite repeat False; native truth True

> Choose option 33 (id 33, fragment 4). Let me verify fragment 4 eligibility: needs [4,1,7,6,11] → paths 1→7 and 6→11. 1→7 exists (node 48, path 1→2→4→7). 6→11 exists (node 53, path 6→8→9→11). Yes eligible.

- Episode 51: derive; F6; span [32309, 32543]; prior 2; definite repeat True; native truth True

> Option 30: fragment 6. Need for fragment 6: row 18: [6,3,8,9,11]. So paths [3,8] and [9,11]. Check source edges: path [3,8]? edges: 3->6, 6->8. Yes path exists (rule 43). Path [9,11]: edge 9->11 exists (rule 34). Both exist. Eligible.

- Episode 52: derive; F0; span [32545, 32709]; prior None; definite repeat False; native truth True

> Option 31: fragment 0. Need row 12: [0,0,7,1,9]. Paths [0,7] and [1,9]. [0,7]: 0->2->4->7 or 0->2->5->7. Yes (rule 47). [1,9]: 1->2->...->9 yes (rule 57). Eligible.

- Episode 53: derive; F2; span [32711, 32857]; prior 9; definite repeat True; native truth True

> Option 32: fragment 2. Need row 14: [2,4,11,5,9]. Paths [4,11] and [5,9]. [4,11]: 4->7->9->11 yes (rule50). [5,9]: 5->7->9 yes (rule42). Eligible.

- Episode 54: derive; F10; span [32859, 33160]; prior None; definite repeat False; native truth False

> Option 34: fragment 10. Need row 22: [10,4,8,5,11]. Paths [4,8] and [5,11]. [4,8]: edges 4->7, 7->9, 9->11... need to reach 8? 6->8, 3->6. From 4 can we get to 8? Paths: 4->7->9->11 no edges to 8 except 6->8. No edge into 6 except 3->6. So [4,8] not reachable. Not eligible. So option 34 inadmissible.

- Episode 55: reuse; F0; span [40406, 40509]; prior None; definite repeat False; native truth True

> But is option 31's fragment eligible? Fragment 0 needs paths [0,7] and [1,9], both exist. Yes eligible.

- Episode 56: reuse; F2; span [40649, 40812]; prior None; definite repeat False; native truth True

> Actually, let me double-check option 32 eligibility: fragment 2, need [2,4,11,5,9]: paths [4,11] and [5,9]. Both exist (rules 50 and 42). Eligible but over budget.

- Episode 58: derive; F6; span [41787, 41879]; prior 2; definite repeat True; native truth True

> Source edges: 3->6, 6->8 (so 3->8 exists). 9->11 exists. Both positive length. Eligible yes.

- Episode 59: derive; F2; span [41957, 42056]; prior 9; definite repeat True; native truth True

> Path 4->11 and 5->9? Let's check source edges: 4->7->9->11 yes; 5->7->9? 5->7->9 yes. Eligible yes.

- Episode 60: derive; F10; span [42344, 42507]; prior None; definite repeat False; native truth False

> Path from 4 to 8: 4->7->9->11? no to 8. 4->7->9... no 8. 8 only incoming from 6; 6 from 3; 3 no incoming from 4. So no path 4->8. Therefore fragment 10 ineligible.

- Episode 61: derive; F10; span [42513, 42591]; prior None; definite repeat False; native truth False

> second path 5->11 exists (5->7->9->11) but first fails. So id 34 inadmissible.

- Episode 65: mention; F10; span [55177, 55222]; prior None; definite repeat False; native truth False

> So need paths 4->8 and 5->11 in source edges.

- Episode 66: derive; F10; span [55321, 55383]; prior None; definite repeat False; native truth False

> Path 4->8: 4->7->9? 9->? 9->11, no 8. 4->7, 7->9, 9->11. No 8.

- Episode 67: derive; F10; span [55384, 55485]; prior None; definite repeat False; native truth False

> Hmm, also 6->8 exists but 4->... can we reach 6? No edges into 6 except 3->6. So 4->8 does not exist.

- Episode 68: uncertain; F10; span [55536, 55637]; prior None; definite repeat False; native truth False

> Node 43 "path" [3,8] via 30,7: 3->6->8. No path 4->8. So fragment 10's first path 4->8 doesn't exist?

- Episode 69: derive; F10; span [55811, 55910]; prior 66; definite repeat False; native truth False

> Path 4->8 in edges: 4->7->9->11, no 8. Also 2->4, but need 4 as start. So first path doesn't exist.

- Episode 70: derive; F10; span [56324, 56388]; prior None; definite repeat False; native truth False

> Check path 5->11: 5->7->9->11 yes (rule 51 path [5,11] node 51).

Rejected labels retained:
[{"annotation":{"claim":"Fragment 4 paths 1→7 and 6→11 exist (1→2→4→7, 6→8→9→11).","explanation":"Explicit edge chains support both required paths for fragment 4.","fragment":4,"kind":"derive","occurrence":0,"paths":[[1,7],[6,11]],"premiseEdges":[[1,2],[2,4],[4,7],[6,8],[8,9],[9,11]],"prior":null,"quote":"fragment 4: need [1,7,6,11]. Path 1→7 exists: 1→2→4→7 (or 1→2→5→7). Path 6→11 exists: 6→8→9→11. Both yes.","ready":true},"chunkFirstCall":2,"failure":"quote not present verbatim","index":2},{"annotation":{"claim":"Fragment 6 paths 3→8 and 9→11 exist (3→6→8, 9→11).","explanation":"Explicit edge chains support both required paths for fragment 6.","fragment":6,"kind":"derive","occurrence":0,"paths":[[3,8],[9,11]],"premiseEdges":[[3,6],[6,8],[9,11]],"prior":null,"quote":"fragment 6: [6,3,8,9,11] means first 3→8 exists 3→6→8; second 9→11 exists 9→11. Both yes.","ready":true},"chunkFirstCall":2,"failure":"quote not present verbatim","index":3},{"annotation":{"claim":"Fragment 4 eligibility via 1→7 and 6→11 paths.","explanation":"Same conclusion and same source-bound ordered direct edges, restated in the same call as option 11 consideration.","fragment":4,"kind":"derive","occurrence":0,"paths":[[1,7],[6,11]],"premiseEdges":[[1,2],[2,4],[4,7],[6,8],[8,9],[9,11]],"prior":2,"quote":"fragment 4 need [1,7,6,11]. Path 1→7: 1→2→4→7 or 1→2→5→7 yes. Path 6→11: 6→8→9→11 yes. So eligible.","ready":true},"chunkFirstCall":2,"failure":"prior annotation was rejected","index":6},{"annotation":{"claim":"Fragment 4 is eligible because both required paths 1->7 and 6->11 exist","explanation":"Conjunction conclusion of both path requirements with edge-chain support.","fragment":4,"kind":"derive","occurrence":0,"paths":[[1,7],[6,11]],"premiseEdges":[[1,2],[2,4],[4,7],[6,8],[8,9],[9,11]],"prior":null,"quote":"Check fragment 4: path 1->7? From 1: 1->2->4->7 yes. path 6->11? From 6: 6->8->9->11 yes. So fragment 4 eligible.","ready":true},"chunkFirstCall":4,"failure":"out of chronological order","index":2},{"annotation":{"claim":"Fragment 6 is eligible because both required paths 3->8 and 9->11 exist","explanation":"Conjunction conclusion for fragment 6 paths.","fragment":6,"kind":"derive","occurrence":0,"paths":[[3,8],[9,11]],"premiseEdges":[[3,6],[6,8],[9,11]],"prior":null,"quote":"Fragment 6: needs[6]=[6,3,8,9,11]. path 3->8? 3->6->8 yes. path 9->11? 9->11 yes. Eligible.","ready":true},"chunkFirstCall":4,"failure":"out of chronological order","index":5},{"annotation":{"claim":"Fragment 0 is eligible because both required paths 0->7 and 1->9 exist","explanation":"Conjunction conclusion for fragment 0.","fragment":0,"kind":"derive","occurrence":0,"paths":[[0,7],[1,9]],"premiseEdges":[[0,2],[2,4],[4,7],[1,2],[7,9]],"prior":null,"quote":"Fragment 0: needs[0]=[0,0,7,1,9]. path 0->7? 0->2->4->7 yes. path 1->9? 1->2->4->7->9 yes. Eligible.","ready":true},"chunkFirstCall":4,"failure":"out of chronological order","index":8},{"annotation":{"claim":"Fragment 2 is eligible because both required paths 4->11 and 5->9 exist","explanation":"Conjunction conclusion for fragment 2.","fragment":2,"kind":"derive","occurrence":0,"paths":[[4,11],[5,9]],"premiseEdges":[[4,7],[7,9],[9,11],[5,7]],"prior":null,"quote":"Fragment 2: needs[2]=[2,4,11,5,9]. path 4->11? 4->7->9->11 yes. path 5->9? 5->7->9 yes. Eligible.","ready":true},"chunkFirstCall":4,"failure":"out of chronological order","index":11},{"annotation":{"claim":"Fragment 9 ineligible because path 3->7 does not exist","explanation":"Negative derivation excluding path 3->7.","fragment":9,"kind":"derive","occurrence":0,"paths":[[3,7]],"premiseEdges":[],"prior":null,"quote":"first 3->7? Let's check directed edges: 3->6->8->9->11, no to 7. Need firstFrom=3 firstTo=7. Is there path 3 to 7? ... no edge to 7. So fragment 9 ineligible? Wait need index 9 [9,3,7,2,9], first path 3->7 does NOT exist.","ready":false},"chunkFirstCall":4,"failure":"quote not present verbatim","index":19},{"annotation":{"claim":"Fragment 10 ineligible because path 4→8 absent","explanation":"Restates the 4→8 ineligibility; repeated conclusion, but occurrence matches the same sentence re-examined rather than a duplicate span occurrence within one run.","fragment":null,"kind":"reuse","occurrence":1,"paths":[[4,8]],"premiseEdges":[[4,7],[7,9]],"prior":null,"quote":"Actually need to check paths: from 4 to 8? edges: 4→7, 5→7, 7→9, etc. No 8 reachable from 4 except... 4→7→9? 9→11. 8→9. So 4 can't reach 8. Ineligible.","ready":null},"chunkFirstCall":6,"failure":"quote not present verbatim","index":6},{"annotation":{"claim":"Fragment 2 eligibility: paths 4→11 and 5→9 both exist","explanation":"Second identical double-check reference to fragment 2 eligibility; same reuse, occurrence 1.","fragment":2,"kind":"reuse","occurrence":1,"paths":[[4,11],[5,9]],"premiseEdges":[],"prior":null,"quote":"Actually, let me double-check option 32 eligibility: fragment 2, need [2,4,11,5,9]: paths [4,11] and [5,9]. Both exist (rules 50 and 42). Eligible but over budget.","ready":true},"chunkFirstCall":6,"failure":"quote not present verbatim","index":14},{"annotation":{"claim":"Fragment 6 both paths exist so option 30 eligible","explanation":"Re-derivation under call 9 reconsideration of option 30, same source-bound qualification as prior call 8 derivation.","fragment":6,"kind":"conditional_recheck","occurrence":0,"paths":[[3,8],[9,11]],"premiseEdges":[[3,6],[6,8],[9,11]],"prior":0,"quote":"Option 30 fragment 6: need [6,3,8,9,11]. Path 3->8 exists via 3->6->8. Path 9->11 exists via 9->11. So eligible. Good.","ready":true},"chunkFirstCall":8,"failure":"repeat link must connect derivations","index":4},{"annotation":{"claim":"Fragment 2 paths 4→11 and 5→9 exist so option 32 eligible","explanation":"Re-derivation of the same fragment 2 eligibility under the call 9 branch reconsideration.","fragment":2,"kind":"conditional_recheck","occurrence":0,"paths":[[4,11],[5,9]],"premiseEdges":[[4,7],[7,9],[9,11],[5,7]],"prior":1,"quote":"Option 32 fragment 2. Path 4->11 exists? 4->7->9->11 yes. Path 5->9 exists? 5->7->9 yes. Eligible.","ready":true},"chunkFirstCall":8,"failure":"repeat link must connect derivations","index":5},{"annotation":{"claim":"Fragment 10 has 5→11 but not 4→8, so option 34 ineligible","explanation":"Reconsideration of fragment 10 eligibility in call 9 branch with the same underlying path failure.","fragment":10,"kind":"conditional_recheck","occurrence":0,"paths":[[4,8],[5,11]],"premiseEdges":[[5,7],[7,9],[9,11]],"prior":2,"quote":"Option 34 fragment 10. Need [10,4,8,5,11] => first 4->8, second 5->11. 4->8? 4->7->9->? no 9->11, no 8. 4->7->9->? not 8. 5->11? 5->7->9->11 yes. First 4->8 not exists likely. So option 34 ineligible.","ready":true},"chunkFirstCall":8,"failure":"repeat link must connect derivations","index":6},{"annotation":{"claim":"Fragment 10 inadmissible because path 4->8 does not exist","explanation":"Concludes fragment 10 fails the both-paths conjunction since 4->8 is missing, derived by conjunction reasoning referencing the two path requirements.","fragment":10,"kind":"derive","occurrence":0,"paths":[[4,8],[5,11]],"premiseEdges":[],"prior":3,"quote":"Path 4->8: does not exist (no derivation node for 4->8). So inadmissible.","ready":false},"chunkFirstCall":10,"failure":"repeat link must connect derivations","index":6}]

## paid/branch-search-6-retained-0

Text SHA `8cfac0a324a9f2816f4b048a4e52219b9a79552a6ce2cb6f84a8e5a0c494c678`; annotation failure `None`.

- Episode 0: derive; F0; span [593, 694]; prior None; definite repeat False; native truth False

> Fragment 0: need [0,0,7,1,9]: path 0->7 exists (rule path [0,7] node 47 from 36+4). Path 1->9 exists?

- Episode 2: derive; F2; span [894, 1000]; prior None; definite repeat False; native truth False

> Fragment 2: need [2,4,11,5,9]: path 2->11 node58 (49+10) exists; path 5->9 node42 (29+8) exists. Eligible.

- Episode 4: derive; F6; span [1260, 1349]; prior None; definite repeat False; native truth True

> Fragment 6: need [6,3,8,9,11]: path 3->8 node43 exists; path 9->11 node34 edge. Eligible.

- Episode 5: derive; F8; span [1351, 1659]; prior None; definite repeat False; native truth True

> Fragment 8: need [8,0,8,1,7]: path 0->8? Is there a path 0 to 8? 0->4->7->9->... no edge to 8. Actually edges: 0->2,1->2,2->4,2->5,4->7,5->7,3->6,6->8,7->9,8->9,9->11,10->11. No path 0->8. So fragment 8 not eligible! Interesting. The unvisited children include option id 4 fragment 8. So that's inadmissible.

- Episode 6: derive; F8; span [8629, 8886]; prior None; definite repeat False; native truth False

> Fragment 8 need row [8,0,8,1,7]. First path from 0 to 8. Edges: is there a directed path 0->...->8? 0->2->4->7->9->11, no 8. 0->2->5->7->9... no. So no path 0->8. Indeed no incoming edges to 8 except from 6. So 0 cannot reach 8. Ineligible. Good, confirmed.

- Episode 8: reuse; F6; span [9586, 9684]; prior None; definite repeat False; native truth True

> Fragment 6 need row index 6: [6,3,8,9,11] -> 3->8 (node43) and 9->11 (node34). Eligible. Option 3.

- Episode 9: reuse; F2; span [9686, 9784]; prior None; definite repeat False; native truth False

> Fragment 2 need row index 2: [2,4,11,5,9] -> 4->11 (node50) and 5->9 (node42). Eligible. Option 1.

- Episode 10: reuse; F0; span [9786, 9876]; prior None; definite repeat False; native truth True

> Fragment 0 need row 0: [0,0,7,1,9] -> 0->7 (node47) and 1->9 (node57). Eligible. Option 0.

- Episode 12: derive; F3; span [12048, 12171]; prior None; definite repeat False; native truth True

> Fragment3: need [3,0,11,3,9]. Paths 0->11 and 3->9. 0->11 exists via 0->2->4->7->9->11 or via 5 etc. 3->9 exists. eligible.

- Episode 13: derive; F5; span [12173, 12283]; prior None; definite repeat False; native truth True

> Fragment5: need [5,2,7,8,11]. Paths 2->7 and 8->11. 2->7 via 2->4->7 or 2->5->7. 8->11 via 8->9->11. eligible.

- Episode 14: derive; F7; span [12285, 12381]; prior None; definite repeat False; native truth True

> Fragment7: need [7,0,9,10,11]. Paths 0->9 and 10->11. 0->9 exists. 10->11 edge exists. eligible.

- Episode 15: derive; F9; span [12383, 12698]; prior None; definite repeat False; native truth True

> Fragment9: need [9,3,7,2,9]. Paths 3->7 and 2->9. 3->7? edges 3->6->8->9; no edge to 7 from 8? 7->9, not 9->7. 3->6->8->9->? 7 no outgoing to 9? Edge 7->9 directed 7 to 9; no 9->7. So 3->7 path maybe 3->6->8? no to 7. 3->6->8->9->11 no. Thus 3->7 does not exist. Fragment 9 inadmissible. So option 9 likely invalid.

- Episode 16: uncertain; F6; span [13383, 13460]; prior None; definite repeat False; native truth False

> Option 6 has best value 257 but risk 36 over limit by 1. Could be repairable.

- Episode 17: mention; FNone; span [15920, 16040]; prior None; definite repeat False; native truth False

> Need check fragment eligibility: option iff both positive-length directed paths of its fragment F exist in source edges.

- Episode 18: derive; F2; span [16642, 16697]; prior None; definite repeat False; native truth True

> fragment 2 need 4->11: edges 4->7->9->11 yes; 5->9 yes.

- Episode 19: derive; F4; span [16698, 16783]; prior None; definite repeat False; native truth True

> fragment 4 need 1->7: 1->2->4->7 or 1->2->5->7 yes; 6->11: 6->8->9->11 yes. eligible.

- Episode 20: derive; F6; span [16784, 16839]; prior None; definite repeat False; native truth True

> fragment 6 need 3->8: 3->6->8 yes; 9->11 yes. eligible.

- Episode 21: derive; F0; span [16840, 16885]; prior None; definite repeat False; native truth True

> fragment 0 need 0->7 yes; 1->9 yes. eligible.

- Episode 22: derive; F10; span [16886, 17038]; prior None; definite repeat False; native truth False

> fragment 10 need 4->8? edges 4->7->9->11, no to 8? 8->9 not reverse. 4 cannot reach 8. second 5->11 yes. So fragment 10 ineligible (first path missing).

- Episode 23: derive; F6; span [19401, 19481]; prior 20; definite repeat True; native truth True

> Check fragment 6 eligible: need 3->8 and 9->11. Source edges yes 3->6->8; 9->11.

- Episode 25: derive; F10; span [26070, 26205]; prior 22; definite repeat False; native truth False

> id14 ineligible due 4->8? Let's double-check fragment10 need [10,4,8,5,11]. Edges 4->7->9->11; no edge to8. 8->9, not 4->8. Ineligible.

- Episode 26: derive; F3; span [28299, 28443]; prior None; definite repeat False; native truth True

> Child option 15, fragment 3: needs paths 0->11 and 3->9.
> Path 0->11: 0->2->4->7->9->11 exists. Yes.
> Path 3->9: 3->6->8->9 exists. Yes.
> Eligible.

- Episode 27: derive; F5; span [28445, 28558]; prior 13; definite repeat True; native truth True

> Child option 16, fragment 5: paths 2->7 and 8->11.
> 2->7: 2->4->7 or 2->5->7. Yes.
> 8->11: 8->9->11. Yes.
> Eligible.

- Episode 28: derive; F7; span [28560, 28674]; prior None; definite repeat False; native truth True

> Child option 17, fragment 7: paths 0->9 and 10->11.
> 0->9: 0->2->4->7->9. Yes.
> 10->11: edge [10,11]. Yes.
> Eligible.

- Episode 29: derive; F1; span [28676, 28787]; prior None; definite repeat False; native truth True

> Child option 18, fragment 1: paths 2->9 and 3->11.
> 2->9: 2->4->7->9. Yes.
> 3->11: 3->6->8->9->11. Yes.
> Eligible.

- Episode 30: derive; F11; span [28789, 28948]; prior None; definite repeat False; native truth False

> Child option 19, fragment 11: paths 10->9 and 0->7.
> 10->9: edges from 10 only to 11. 10->11, then 11 has no outgoing edges. So 10->9 doesn't exist. Ineligible.

- Episode 31: derive; F0; span [33657, 33704]; prior 21; definite repeat True; native truth True

> fragment 0: [0,0,7,1,9] => paths 0->7 and 1->9.

- Episode 32: derive; F4; span [34063, 34193]; prior 19; definite repeat True; native truth True

> Option id20 fragment 4: paths 1->7 and 6->11. Edges: Is 1->7 path? 1->2->4->7 or 1->2->5->7 yes. 6->11? 6->8->9->11 yes. Eligible.

- Episode 33: derive; F6; span [34195, 34281]; prior 20; definite repeat True; native truth True

> Option id21 fragment 6: paths 3->8 and 9->11. 3->6->8 yes. 9->11 direct yes. Eligible.

- Episode 34: derive; F0; span [34283, 34407]; prior None; definite repeat False; native truth True

> Option id22 fragment 0: paths 0->7 and 1->9. 0->7 via 0->2->4->7 yes. 1->9 via 1->2->4->7->9 or 1->2->5->7->9 yes. Eligible.

- Episode 35: derive; F2; span [34409, 34534]; prior None; definite repeat False; native truth False

> Option id23 fragment 2: paths 2->11 and 5->9. 2->11 via 2->4->7->9->11 or 2->5->7->9->11 yes. 5->9 via 5->7->9 yes. Eligible.

- Episode 36: derive; F8; span [34536, 34772]; prior None; definite repeat False; native truth False

> Option id24 fragment 8: paths 0->8 and 1->7. 0->8? Edges: 0->2, then 2->4/5, 4->7/5->7, 7->9,9->11, no edge to 6 or8? 6->8 only from 3->6, so no path to 8. Thus not eligible? Need both paths exist. 0->8 not exists. So id24 inadmissible.

- Episode 37: derive; F5; span [36739, 37166]; prior None; definite repeat False; native truth True

> id25 fragment5: needs row fragment 5 = [5,2,7,8,11] (from evidence node17 source need [5,2,7,8,11]) i.e first path from 2 to7? Wait columns: fragmentId, firstFrom, firstTo, secondFrom, secondTo. For fragment 5 need [5,2,7,8,11]: first path 2->7, second 8->11. Need both positive-length directed paths exist in source edges. Edges directed list. 2->7 path? 2->4->7 exists (edges 2->4,4->7). 8->11? 8->9->11 exists. Eligible yes.

- Episode 38: derive; F7; span [37168, 37298]; prior 28; definite repeat True; native truth True

> id26 fragment7: need [7,0,9,10,11]: first 0->9, second 10->11. 0->9 exists? edges 0->2->4->7->9 yes. 10->11 edge exists. Eligible.

- Episode 39: derive; F1; span [37300, 37412]; prior 29; definite repeat True; native truth True

> id27 fragment1: need [1,2,9,3,11]: first 2->9? edges 2->4->7->9 yes. second 3->11? 3->6->8->9->11 yes. Eligible.

- Episode 40: derive; F9; span [37504, 37723]; prior None; definite repeat False; native truth False

> id29 fragment9: need [9,3,7,2,9]: first 3->7? edges 3->6->8->9... no 9->? wait firstFrom 3 to7. Is there path 3->7? Edges: 3->6,6->8,8->9,9->11,10->11... no edge to7 from those. 3->6->8->9->? no 7. So ineligible likely.

- Episode 41: reuse; F3; span [42450, 42633]; prior None; definite repeat False; native truth True

> Fragment3 need row [3,0,11,3,9]: both paths 0->11 and 3->9 exist. Yes. However option 28 fragment 3: in need row [3,0,11,3,9]. first path 0->11 yes; second path 3->9 yes. So eligible.

- Episode 42: derive; F6; span [43796, 43957]; prior 20; definite repeat True; native truth True

> Fragment 6: needs [6,3,8,9,11] → first path 3→8, second path 9→11. Path 3→8: edges 3→6, 6→8. Yes exists (rule 43 path [3,8]). Path 9→11: edge 9→11 yes. Eligible.

- Episode 43: derive; F0; span [43959, 44098]; prior 34; definite repeat True; native truth True

> Fragment 0: needs [0,0,7,1,9] → path 0→7 and 1→9. 0→7: 0→2→4→7 (edges 0-2,2-4,4-7) yes. 1→9: 1→2→4→7→9, yes (rule 57 path [1,9]). Eligible.

- Episode 44: derive; F2; span [44100, 44197]; prior None; definite repeat False; native truth True

> Fragment 2: needs [2,4,11,5,9] → path 4→11 and 5→9. 4→11: 4→7→9→11 yes. 5→9: 5→7→9 yes. Eligible.

- Episode 45: derive; F4; span [44199, 44298]; prior 19; definite repeat True; native truth True

> Fragment 4: needs [4,1,7,6,11] → path 1→7 and 6→11. 1→7: 1→2→4→7 yes. 6→11: 6→8→9→11 yes. Eligible.

- Episode 46: derive; F10; span [44300, 44517]; prior None; definite repeat False; native truth False

> Fragment 10: needs [10,4,8,5,11] → path 4→8? edges: 4→7→9, 9→... no 8. Path 4→8: 4→7,7→9,9→11; 8 not reachable from 4? 4→7→9→11. 8 connects to 9 (8→9), but 9 doesn't go to 8. So no path 4→8. So fragment 10 ineligible.

- Episode 47: reuse; F6; span [48469, 48557]; prior None; definite repeat False; native truth True

> id30 fragment 6: paths 3->8 (node43 exists) and 9->11 (node34/10 edge exists). Eligible.

- Episode 50: reuse; F0; span [50217, 50340]; prior None; definite repeat False; native truth True

> Fragment 0: need row [0, 0,7,1,9] → paths 0→7 and 1→9. From derivation: 47 path [0,7], 57 path [1,9]. Both exist. Eligible.

- Episode 51: reuse; F2; span [50342, 50451]; prior None; definite repeat False; native truth True

> Fragment 2: need row [2, 4,11,5,9] → paths 4→11 and 5→9. 50 path [4,11], 42 path [5,9]. Both exist. Eligible.

- Episode 52: derive; F10; span [50453, 50727]; prior None; definite repeat False; native truth True

> Fragment 10: need row [10, 4,8,5,11] → paths 4→8 and 5→11. 4→8? edges: 4→7→9... no 4→8 path. Actually 4→11→... hmm 4→8: from edges, 4→7,7→9,9→11. 8 is reachable from 3→6→8. Is there 4→8? No. So fragment 10 ineligible. Also 5→11 exists (51). But 4→8 doesn't. So inadmissible.

- Episode 53: derive; F2; span [51820, 51947]; prior 44; definite repeat True; native truth True

> Check fragment 2: need paths 4->11 and 5->9. Source edges include 4->7->9->11 so path 4 to 11 exists. 5->7->9 yes. So eligible.

- Episode 55: mention; F10; span [53621, 53687]; prior None; definite repeat False; native truth False

> Fragment 10 needs [10,4,8,5,11]: first path 4->8 and second 5->11.

- Episode 56: derive; F10; span [53746, 53784]; prior None; definite repeat False; native truth False

> Is there path 4->8? 4->7->9->11, no 8.

- Episode 57: derive; F10; span [53785, 53845]; prior None; definite repeat False; native truth False

> So first path 4->8 does not exist. Thus fragment ineligible.

Rejected labels retained:
[{"annotation":{"claim":"Fragment 0 is eligible because 0->7 and 1->9 both exist; 1->9 via 1->7->9","explanation":"Conjunction conclusion for F0 with edge-chain support claimed for 1->9.","fragment":0,"kind":"derive","occurrence":0,"paths":[[0,7],[1,9]],"premiseEdges":[[1,2],[1,4],[1,7],[7,9]],"prior":null,"quote":"48 path [1,7] from 38+4, 38 path[1,4] from 25+2, 25 path[1,2] edge. 8 path [7,9] edge. So 1->7->9. Yes exists. Both positive length. Fragment 0 eligible.","ready":true},"chunkFirstCall":0,"failure":"support edge outside source","index":1},{"annotation":{"claim":"Fragment 4 is eligible because 1->7 and 6->11 exist; 6->11 via 6->9->11","explanation":"Conjunction conclusion for F4 with partial edge-chain support for 6->11.","fragment":4,"kind":"derive","occurrence":0,"paths":[[1,7],[6,11]],"premiseEdges":[[6,9],[9,11]],"prior":null,"quote":"Fragment 4: need [4,1,7,6,11]: path 4->? wait need row index 4: [4,1,7,6,11] means fragmentId 4, firstFrom 1, firstTo 7, secondFrom 6, secondTo 11. Path 1->7 node48 exists; path 6->11 node53 exists (44+10: 44 path[6,9] from 31+9, 10 edge [9,11]). Eligible.","ready":true},"chunkFirstCall":0,"failure":"support edge outside source","index":3},{"annotation":{"claim":"Fragment 4 eligible; paths 1->7 and 6->11 both exist","explanation":"Restates previously derived F4 eligibility via node IDs; reuse rather than new derivation.","fragment":4,"kind":"reuse","occurrence":0,"paths":[[1,7],[6,11]],"premiseEdges":[],"prior":null,"quote":"Fragment 4 need row: index 4 in needs list: [4,1,7,6,11] -> firstFrom 1, firstTo 7, secondFrom 6, secondTo 11. Paths 1->7 (node48) and 6->11 (node53). Both exist. Eligible. Option 2.","ready":true},"chunkFirstCall":0,"failure":"quote not present verbatim","index":7},{"annotation":{"claim":"Fragment 1 eligible because 2->9 and 3->11 exist","explanation":"Conjunction conclusion for F1 with explicit edge chains.","fragment":1,"kind":"derive","occurrence":0,"paths":[[2,9],[3,11]],"premiseEdges":[[2,4],[4,7],[7,9],[3,6],[6,8],[8,9],[9,11]],"prior":null,"quote":"Fragment 1: need [1,2,9,3,11], so paths 2->9 and 3->11 must exist. Source edges: [1,2],[2,4],[2,5],[4,7],[5,7],[3,6],[6,8],[7,9],[8,9],[9,11]. Does 2->9 path exist? 2->4->7->9 yes. 3->11? 3->6->8->9->11 yes. eligible.","ready":true},"chunkFirstCall":0,"failure":"quote not present verbatim","index":11},{"annotation":{"claim":"Fragment 0 is eligible because 0 reaches 7 and 1 reaches 9.","explanation":"Re-states fragment 0 eligibility with explicit edge chains supporting both required paths.","fragment":0,"kind":"derive","occurrence":0,"paths":[[0,7],[1,9]],"premiseEdges":[[0,2],[2,4],[4,7],[1,2],[2,5],[5,7],[7,9]],"prior":4,"quote":"But we must check if fragment 0 eligible: fragment 0 needs [0,0,7,1,9], both paths: 0->7 exists (0->2->4->7 or 0->2->5->7), 1->9 exists (1->2->4->7->9 or 1->2->5->7->9). Yes.","ready":true},"chunkFirstCall":2,"failure":"different conclusion/premise context","index":7},{"annotation":{"claim":"Fragment 0 eligible: 0→7 via 0-2-4-7 and 1→9","explanation":"New derivation with explicit edges for 0→7 and reference for 1→9.","fragment":0,"kind":"derive","occurrence":0,"paths":[[0,7],[1,9]],"premiseEdges":[[0,2],[2,4],[4,7]],"prior":null,"quote":"0: [0,0,7,1,9] paths 0->7 and 1->9. Check edges: 0->7 path exists (0-2-4-7 via derivation node 47). 1->9 exists (node 57). Eligible.","ready":true},"chunkFirstCall":6,"failure":"out of chronological order","index":6},{"annotation":{"claim":"Fragment 6 needs are paths 3→8 and 9→11","explanation":"Lists needs rows without inference.","fragment":6,"kind":"mention","occurrence":0,"paths":[[3,8],[9,11]],"premiseEdges":[],"prior":null,"quote":"6: [6,3,8,9,11] paths 3->8 and 9->11.","ready":null},"chunkFirstCall":6,"failure":"out of chronological order","index":7},{"annotation":{"claim":"Fragment 10 needs paths 4→8 and 5→11; no 4→8 path, so not eligible.","explanation":"New derivation of the same fragment-10 conjunction conclusion from same source edges, via edge-chain analysis; prior points to the first fragment-10 derivation.","fragment":10,"kind":"derive","occurrence":0,"paths":[[4,8],[5,11]],"premiseEdges":[[5,7],[7,9],[9,11]],"prior":2,"quote":"Fragment 10: need [10,4,8,5,11] i.e. 4->8 and 5->11. 4->8? edges 4->7->9->11, no 8. Actually 4->7->9, 9->11, no 8. 5->11 via 5->7->9->11 yes. 4->8? There is no edge to 8 except 6->8. No path 4->8. So fragment 10 not eligible.","ready":false},"chunkFirstCall":8,"failure":"different conclusion/premise context","index":4}]

## paid/branch-search-6-retained-1

Text SHA `f25bb2827a05e4b0387ea43a9b25b06d27286bed3e3f94d95f96c02467eb5295`; annotation failure `None`.

- Episode 0: derive; F0; span [692, 768]; prior None; definite repeat False; native truth True

> Fragment 0: 0→7? path 0→2→4→7 yes. 1→9? 1→2→4→7→9 yes. Both exist. Eligible.

- Episode 1: derive; F2; span [770, 827]; prior None; definite repeat False; native truth True

> Fragment 2: 4→11? 4→7→9→11 yes. 5→9? 5→7→9 yes. Eligible.

- Episode 2: derive; F4; span [829, 888]; prior None; definite repeat False; native truth True

> Fragment 4: 1→7? 1→2→4→7 yes. 6→11? 6→8→9→11 yes. Eligible.

- Episode 3: derive; F6; span [890, 928]; prior None; definite repeat False; native truth True

> Fragment 6: 3→8? 3→6→8 yes. 9→11? yes.

- Episode 4: derive; F8; span [1052, 1165]; prior None; definite repeat False; native truth False

> 8 predecessors: 6→8. 6 predecessors: 3→6. So 0→8 requires 0→3 somehow, but no edge into 3. So 0→8 does not exist.

- Episode 5: derive; F8; span [1166, 1193]; prior None; definite repeat False; native truth False

> So fragment 8 NOT eligible.

- Episode 7: derive; F3; span [3491, 3605]; prior None; definite repeat False; native truth True

> id6 fragment3: needs [3,0,11,3,9]. Path 0->11 exists? 0->2->4->7->9->11 yes. 3->9 exists 3->6->8->9 yes. eligible.

- Episode 8: derive; F5; span [3607, 3691]; prior None; definite repeat False; native truth True

> id7 fragment5: needs [5,2,7,8,11]. 2->7 exists. 8->11 exists 8->9->11 yes. eligible.

- Episode 9: derive; F7; span [3693, 3760]; prior None; definite repeat False; native truth True

> id8 fragment7: [7,0,9,10,11]. 0->9 exists. 10->11 exists. eligible.

- Episode 10: derive; F9; span [3762, 3898]; prior None; definite repeat False; native truth False

> id9 fragment9: [9,3,7,2,9]. 3->7? Source edges: 3->6->8->9, but no edge to 7. Also maybe 3->6->8->9->? no 9->11; 3->7 no. So ineligible.

- Episode 12: derive; F2; span [13998, 14130]; prior 1; definite repeat True; native truth True

> id10 fragment2: need row [2,4,11,5,9] => paths 4->11 and 5->9 in source. Edges: 4->7->9->11 yes path 4 to 11. 5->7->9 yes. eligible.

- Episode 13: derive; F4; span [14131, 14232]; prior 2; definite repeat True; native truth True

> id11 fragment4: need [4,1,7,6,11] => paths 1->7 and 6->11. 1->2->4->7 yes. 6->8->9->11 yes. eligible.

- Episode 14: derive; F6; span [14233, 14332]; prior 3; definite repeat True; native truth True

> id12 fragment6: need [6,3,8,9,11] => paths 3->8 and 9->11. 3->6->8 yes. 9->11 direct yes. eligible.

- Episode 15: derive; F0; span [14333, 14434]; prior 0; definite repeat True; native truth True

> id13 fragment0: need [0,0,7,1,9] => paths 0->7 and 1->9. 0->2->4->7 yes. 1->2->4->7->9 yes. eligible.

- Episode 16: derive; F10; span [14435, 14659]; prior None; definite repeat False; native truth True

> id14 fragment10: need [10,4,8,5,11] => paths 4->8 and 5->11. 4->7->9->11? Need 4->8: 4->7->9->... no edge to 8; 4->7, 7->9, 9->11, 8? no. 4->? no to 8. There is 6->8 but not reachable from 4? 4->7->9->11 no. So not eligible.

- Episode 17: derive; F2; span [20180, 20253]; prior 12; definite repeat True; native truth True

> - id10 frag2 paths 4->11 yes (4->7->9->11), 5->9 yes (5->7->9). eligible.

- Episode 18: derive; F4; span [20254, 20326]; prior 13; definite repeat True; native truth True

> - id11 frag4 paths 1->7 yes 1->2->4->7; 6->11 yes 6->8->9->11. eligible.

- Episode 19: derive; F6; span [20327, 20384]; prior 14; definite repeat True; native truth True

> - id12 frag6 paths 3->8 yes 3->6->8; 9->11 yes. eligible.

- Episode 22: mention; F3; span [22873, 22906]; prior None; definite repeat False; native truth False

> fragment 3: paths 0->11 and 3->9.

- Episode 23: mention; F5; span [22907, 22940]; prior None; definite repeat False; native truth False

> fragment 5: paths 2->7 and 8->11.

- Episode 24: mention; F7; span [22941, 22975]; prior None; definite repeat False; native truth False

> fragment 7: paths 0->9 and 10->11.

- Episode 25: mention; F1; span [22976, 23009]; prior None; definite repeat False; native truth False

> fragment 1: paths 2->9 and 3->11.

- Episode 26: mention; F11; span [23010, 23044]; prior None; definite repeat False; native truth False

> fragment 11: paths 10->9 and 0->7.

- Episode 27: derive; F3; span [23159, 23243]; prior 7; definite repeat True; native truth True

> Check fragment 3: 0->11 path? 0->2->4->7->9->11 yes; 3->9? 3->6->8->9 yes. Eligible.

- Episode 28: derive; F5; span [23245, 23315]; prior None; definite repeat False; native truth True

> fragment5: 2->7 yes 2->4->7 or 2->5->7. 8->11? 8->9->11 yes. Eligible.

- Episode 29: derive; F7; span [23317, 23359]; prior None; definite repeat False; native truth True

> fragment7: 0->9 yes; 10->11 yes. Eligible.

- Episode 30: derive; F1; span [23361, 23429]; prior None; definite repeat False; native truth True

> fragment1: 2->9 yes 2->4->7->9; 3->11? 3->6->8->9->11 yes. Eligible.

- Episode 31: derive; F11; span [23431, 23527]; prior None; definite repeat False; native truth True

> fragment11: 10->9? No edge from 10 except 10->11. No path 10 to 9 (directed). Thus inadmissible.

- Episode 32: derive; F4; span [26467, 26685]; prior 2; definite repeat True; native truth True

> Fragment 4 need [4,1,7,6,11] = need two paths: 1->7 and 6->11. Must both exist in source edges positive-length directed paths. 1->7? edges: 1->2->4->7 yes (1-2,2-4,4-7). 6->11? 6->8->9->11 yes (6-8,8-9,9-11). Eligible.

- Episode 33: derive; F6; span [26689, 26766]; prior 3; definite repeat True; native truth True

> option21 fragment6 need [6,3,8,9,11]: 3->8? 3->6->8 yes. 9->11 yes. Eligible.

- Episode 34: derive; F0; span [26770, 26894]; prior None; definite repeat False; native truth True

> option22 fragment0 need [0,0,7,1,9]: 0->7? 0->2->4->7 or 0->2->5->7 yes. 1->9? 1->2->4->7->9 or 1->2->5->7->9 yes. Eligible.

- Episode 35: derive; F2; span [26898, 26988]; prior None; definite repeat False; native truth True

> option23 fragment2 need [2,4,11,5,9]: 4->11? 4->7->9->11 yes. 5->9? 5->7->9 yes. Eligible.

- Episode 36: derive; F5; span [34015, 34134]; prior None; definite repeat False; native truth True

> Check fragment 5: need [5,2,7,8,11]. Paths: 2->7 exists (2->4->7 yes via edges). 8->11 exists (8->9->11 yes). Eligible.

- Episode 37: derive; F7; span [34136, 34243]; prior 29; definite repeat True; native truth True

> Fragment 7: need [7,0,9,10,11]. 0->9 exists (0->2->...->9 yes). 10->11 exists (edge [10,11] yes). Eligible.

- Episode 38: derive; F1; span [34245, 34325]; prior None; definite repeat False; native truth True

> Fragment 1: need [1,2,9,3,11]. 2->9 exists. 3->11: 3->6->8->9->11 yes. Eligible.

- Episode 39: derive; F3; span [34327, 34403]; prior None; definite repeat False; native truth True

> Fragment 3: need [3,0,11,3,9]. 0->11 exists. 3->9: 3->6->8->9 yes. Eligible.

- Episode 40: derive; F9; span [34405, 34772]; prior None; definite repeat False; native truth False

> Fragment 9: need [9,3,7,2,9]. 3->7: 3->6->8->9->... hmm 3->7? edges: 3->6->8->9->11. No edge to 7. Actually 7 is reachable? 3->6->8->9. From 9 ->11. No 7. So 3->7 path doesn't exist. Fragment 9 ineligible! Wait need is [9,3,7,2,9]: firstFrom=3, firstTo=7. Path 3->7? Edges have [7,9] so 7->9, not 3->7. No path 3->7. So fragment 9 ineligible → option 29 inadmissible.

- Episode 42: derive; F0; span [37573, 37654]; prior None; definite repeat False; native truth True

> f0: [0,0,7,1,9] => path 0->7? edges 0->2->4->7 yes. path 1->9? 1->2->4->7->9 yes.

- Episode 43: derive; F1; span [37655, 37723]; prior 30; definite repeat True; native truth True

> f1: [1,2,9,3,11] => 2->9? 2->4->7->9 yes. 3->11? 3->6->8->9->11 yes.

- Episode 44: derive; F2; span [37724, 37786]; prior 35; definite repeat True; native truth True

> f2: [2,4,11,5,9] => 4->11? 4->7->9->11 yes. 5->9? 5->7->9 yes.

- Episode 45: derive; F3; span [37787, 37839]; prior 39; definite repeat True; native truth True

> f3: [3,0,11,3,9] => 0->11 yes, 3->9? 3->6->8->9 yes.

- Episode 46: derive; F4; span [37840, 37905]; prior 2; definite repeat True; native truth True

> f4: [4,1,7,6,11] => 1->7? 1->2->4->7 yes. 6->11? 6->8->9->11 yes.

- Episode 47: derive; F5; span [37906, 37965]; prior 36; definite repeat True; native truth True

> f5: [5,2,7,8,11] => 2->7? 2->4->7 yes. 8->11? 8->9->11 yes.

- Episode 48: derive; F6; span [37966, 38016]; prior None; definite repeat False; native truth True

> f6: [6,3,8,9,11] => 3->8? 3->6->8 yes. 9->11? yes.

- Episode 49: derive; F7; span [38017, 38059]; prior 9; definite repeat True; native truth True

> f7: [7,0,9,10,11] => 0->9 yes. 10->11 yes.

- Episode 50: derive; F8; span [38060, 38193]; prior None; definite repeat False; native truth False

> f8: [8,0,8,1,7] => 0->8? 0->2->4->7->9? to 8 no, but 0->2->? 2->5->7->9->? 8 no. Actually edge 6->8 but 0 to 6? no. So f8 ineligible.

- Episode 51: derive; F10; span [38247, 38510]; prior None; definite repeat False; native truth True

> f10 needs [10,4,8,5,11]. Check 4->8? edges 4->7->9, cannot reach 8 (8->9 only, no 7->8). 5->11? 5->7->9->11 yes. So f10 ineligible? Need both positive-length directed paths. Fragment 10 first path from 4 to 8 does not exist. So option id34 fragment 10 ineligible.

- Episode 52: mention; F4; span [40092, 40197]; prior None; definite repeat False; native truth False

> id33 fragment4 has prefixTotals cost51 risk34 value308, lower value than incumbent 349, but under limits.

- Episode 53: mention; F2; span [40360, 40489]; prior None; definite repeat False; native truth False

> id32 cost57 exceeds costLimit 54 (prefix cost 57 > limit) - prefix resource limit cannot be repaired; should not choose if avoid.

- Episode 54: derive; F4; span [48953, 49068]; prior 46; definite repeat True; native truth True

> But need consider eligibility of f4: f4 needs [4,1,7,6,11]. 1->7: 1->2->4->7 yes. 6->11: 6->8->9->11 yes. Eligible.

- Episode 56: derive; F2; span [50788, 50871]; prior 44; definite repeat True; native truth True

> frag2: row [2,4,11,5,9]. Paths 4->11: 4->7->9->11 yes. 5->9: 5->7->9 yes. eligible.

- Episode 59: reuse; F10; span [54977, 55051]; prior None; definite repeat False; native truth False

> Need check eligibility. Since id34 fragment10 ineligible. Others eligible.

- Episode 60: mention; FNone; span [65543, 65598]; prior None; definite repeat False; native truth False

> Option id31 is id 31, not fragment ID. Call expand(31).

- Episode 61: derive; F6; span [66620, 66667]; prior None; definite repeat False; native truth False

> path 3->8: edges [3,6],[6,8] gives 3->6->8 yes.

- Episode 62: derive; F6; span [66668, 66696]; prior None; definite repeat False; native truth False

> path 9->11: edge [9,11] yes.

- Episode 63: derive; F6; span [66697, 66720]; prior None; definite repeat False; native truth True

> So fragment 6 eligible.

- Episode 64: derive; F2; span [66784, 66839]; prior None; definite repeat False; native truth False

> Path 4->11: 4->7->9->11 yes (edges [4,7],[7,9],[9,11]).

- Episode 65: derive; F2; span [66840, 66858]; prior None; definite repeat False; native truth False

> 5->9: 5->7->9 yes.

- Episode 66: derive; F2; span [66840, 66868]; prior None; definite repeat False; native truth True

> 5->9: 5->7->9 yes. Eligible.

- Episode 67: derive; F10; span [67010, 67115]; prior None; definite repeat False; native truth False

> From 4 can we reach 8? edges: 4->7, 7->9, 9->11, 8->9... no edge to 8 except 6->8. So 4->8 not reachable.

- Episode 68: derive; F10; span [67116, 67142]; prior None; definite repeat False; native truth False

> So fragment 10 ineligible.

- Episode 69: reuse; FNone; span [67144, 67242]; prior None; definite repeat False; native truth False

> So eligible children among options: 30 (frag 6) and 32 (frag 2). Option 34 (frag 10) inadmissible.

Rejected labels retained:
[{"annotation":{"claim":"Fragment 1 has both required paths, so eligible.","explanation":"Conjunction conclusion for fragment 1 with explicit supporting edge chains for both required paths.","fragment":1,"kind":"derive","occurrence":0,"paths":[[2,9],[3,11]],"premiseEdges":[[2,4],[4,7],[7,9],[2,5],[5,7],[3,6],[6,8],[8,9],[9,11]],"prior":null,"quote":"id5 fragment1: needs row 1? Need [1,2,9,3,11]? Wait needs list indexing: [fragmentId, firstFrom, firstTo, secondFrom, secondTo]. For fragment 1: [1,2,9,3,11]. Need both directed paths 2->9 and 3->11 exist in source edges. Path 2->9 exists (2->4->7->9 or 2->5->7->9). Path 3->11? 3->6->8->9->11 exists. Eligible.","ready":true},"chunkFirstCall":0,"failure":"quote not present verbatim","index":6},{"annotation":{"claim":"Fragment 4 has both required paths, so eligible.","explanation":"A later repeat of the same fragment 4 eligibility derivation in the text, but within this annotation extraction it is a reuse of the earlier established conclusion rather than a new independent branch derivation.","fragment":4,"kind":"reuse","occurrence":0,"paths":[[1,7],[6,11]],"premiseEdges":[[1,2],[2,4],[4,7],[6,8],[8,9],[9,11]],"prior":null,"quote":"Fragment 4: 1→7? 1→2→4→7 yes. 6→11? 6→8→9→11 yes. Eligible.","ready":true},"chunkFirstCall":0,"failure":"out of chronological order","index":11},{"annotation":{"claim":"Recheck: fragment 0's paths 0->7 and 1->9 exist.","explanation":"Brief restated derivation of fragment 0 eligibility; support edges omitted in this quote.","fragment":0,"kind":"derive","occurrence":0,"paths":[[0,7],[1,9]],"premiseEdges":[],"prior":3,"quote":"- id13 frag0 paths 0->7 yes; 1->9 yes. eligible.","ready":true},"chunkFirstCall":2,"failure":"different conclusion/premise context","index":8},{"annotation":{"claim":"Recheck: fragment 10 is ineligible because 4 cannot reach 8.","explanation":"Negative recheck for fragment 10 eligibility, confirming no 4->8 path.","fragment":10,"kind":"derive","occurrence":0,"paths":[[4,8],[5,11]],"premiseEdges":[[4,7],[7,9],[9,11],[6,8]],"prior":4,"quote":"- id14 frag10 paths 4->8? Let's verify source edges maybe 4->? 4->7; 7->9; 9->11; no 8. There is 6->8. 4 cannot reach 8. So ineligible reject.","ready":false},"chunkFirstCall":2,"failure":"different conclusion/premise context","index":9},{"annotation":{"claim":"Fragment 3 eligible: 0->11 via 0-2-4-7-9-11 and 3->9 via 3-6-8-9.","explanation":"Re-check of fragment 3 eligibility expanding the previously elided 0->11 chain; same source context and same conclusion, so this is a repeated derivation of fragment 3.","fragment":3,"kind":"conditional_recheck","occurrence":0,"paths":[[0,11],[3,9]],"premiseEdges":[[0,2],[2,4],[4,7],[7,9],[9,11],[3,6],[6,8],[8,9]],"prior":7,"quote":"Wait need to double-check fragment 3 paths in source edges: first path 0->11: edges 0->2->4->7->9->11 yes. second 3->9: 3->6->8->9 yes. Eligible.","ready":true},"chunkFirstCall":4,"failure":"repeat link must connect derivations","index":9},{"annotation":{"claim":"Fragment 0 satisfies both required paths: 0->7 via 0->2->4->7 or 0->2->5->7 and 1->9 via 1->2->4->7->9 or 1->2->5->7->9.","explanation":"Re-derives fragment 0 conjunction with alternative path witnesses in the same context.","fragment":0,"kind":"derive","occurrence":0,"paths":[[0,7],[1,9]],"premiseEdges":[[0,2],[2,4],[4,7],[2,5],[5,7],[1,2],[2,4],[4,7],[7,9],[1,2],[2,5],[5,7],[7,9]],"prior":0,"quote":"frag0: row [0,0,7,1,9]. Paths 0->7: edges 0->2->4->7 or 0->2->5->7 yes. 1->9: 1->2->4->7->9 or 1->2->5->7->9 yes. eligible.","ready":true},"chunkFirstCall":6,"failure":"different conclusion/premise context","index":13},{"annotation":{"claim":"Fragment 10 is ineligible because no path 4->8 exists.","explanation":"Re-derives the same fragment 10 ineligibility with the same missing-path reasoning.","fragment":10,"kind":"derive","occurrence":0,"paths":[[4,8]],"premiseEdges":[[6,8]],"prior":9,"quote":"frag10: row [10,4,8,5,11]. Paths 4->8? Edges: 4->7->9, no edge to8. 8->9, but from4 cannot reach8? 4->7->9, 7->9, 9->11, no. There is no path 4->8 (8 has incoming 6 only? edges 6->8, and maybe 8 out 9. 4 can't reach 6). So fragment10 not eligible.","ready":false},"chunkFirstCall":6,"failure":"different conclusion/premise context","index":15},{"annotation":{"claim":"Fragment 6 satisfies both required paths: 3->8 via 3->6->8 and 9->11 directly.","explanation":"Re-derives the same fragment 6 conjunction with identical edge premises in the same reasoning context.","fragment":6,"kind":"derive","occurrence":0,"paths":[[3,8],[9,11]],"premiseEdges":[[3,6],[6,8]],"prior":6,"quote":"frag 6: need row? evidence derivation nodes 18 source need [6,3,8,9,11] => fragmentId6, firstFrom3 firstTo8, secondFrom9 secondTo11.\nCheck directed paths 3->8 in edges: edges [3,6],[6,8] yes path length2. 9->11 edge [9,11] yes. Eligible if both exist. Fragment6 eligible.","ready":true},"chunkFirstCall":6,"failure":"out of chronological order","index":16}]

