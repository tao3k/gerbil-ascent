# Frozen direct-derivation annotations, branch search

Source text is returned external-model reasoning. Exact half-open Unicode character spans are validated. Definite repeats require an earlier grounded derivation with identical conclusion and ordered explicit premises; alternative witnesses and goal-dependent checks remain separate. Extraction is not independent human ground truth.

## paid/branch-search-4-baseline-0

Text SHA `35cc38f7be21cc193fc348bbb062e97915c36f4ea41c075f046faa6268f817d9`; annotation failure `None`.

- Episode 0: derive; F0; span [456, 533]; prior None; definite repeat False; native truth True

> Check directed paths 0->7: 0->2->4->7 yes. 1->9: 1->2->4->7->9 yes. Eligible.

- Episode 1: derive; F2; span [562, 614]; prior None; definite repeat False; native truth True

> 4->11: 4->7->9->11 yes. 5->9: 5->7->9 yes. Eligible.

- Episode 2: derive; F4; span [643, 709]; prior None; definite repeat False; native truth True

> 1->7: 1->2->4->7 or 2->5->7 yes. 6->11: 6->8->9->11 yes. Eligible.

- Episode 3: derive; F6; span [738, 784]; prior None; definite repeat False; native truth True

> 3->8: 3->6->8 yes. 9->11: 9->11 yes. Eligible.

- Episode 4: derive; F8; span [978, 1054]; prior None; definite repeat False; native truth False

> fragment8 ineligible? first path 0->8 absent. Thus exclude id4 despite good.

- Episode 6: derive; F6; span [5311, 5378]; prior None; definite repeat False; native truth True

> fragment 6: [6,3,8,9,11] -> 3->8? 3->6->8 yes. 9->11 yes. eligible.

- Episode 7: derive; F7; span [5379, 5468]; prior None; definite repeat False; native truth True

> fragment 7: [7,0,9,10,11] -> 0->9? 0->2->4->7->9 yes. 10->11 yes. eligible. (Option id 8)

- Episode 8: derive; F9; span [5586, 5705]; prior None; definite repeat False; native truth False

> fragment 9: [9,3,7,2,9] -> 3->7? 3->6->8->9->11? no 7. 2->9? 2->4->7->9 yes. second path maybe first fails. ineligible.

- Episode 9: derive; F11; span [5823, 5923]; prior None; definite repeat False; native truth False

> fragment 11: [11,10,9,0,7] -> 10->9? 10->11 only. no. 0->7? 0->2->4->7 yes. first fails. ineligible.

- Episode 10: derive; F2; span [10564, 10806]; prior 1; definite repeat True; native truth True

> For fragment 2: firstFrom=4 firstTo=11; secondFrom=5 secondTo=9.
> Paths in edges: 4->7 (2,4? edge 2->4 not 4->7? Actually [2,4] means 2->4; [4,7] means 4->7; [5,7]; [7,9]; [9,11]. So 4->7->9->11 exists. 5->7->9 exists. Both positive. Eligible.

- Episode 11: derive; F4; span [10808, 10959]; prior 2; definite repeat True; native truth True

> Option 11 fragment 4: row fragment 4 [4,1,7,6,11]. Paths: 1->7? edges 1->2->4->7 or 1->2->5->7 exists. 6->11? edges 3->6? 6->8->9->11 exists. Eligible.

- Episode 12: derive; F6; span [10961, 11059]; prior 3; definite repeat True; native truth True

> Option 12 fragment 6: row [6,3,8,9,11]. 3->8? edges 3->6->8 exists. 9->11 direct exists. Eligible.

- Episode 13: derive; F0; span [11061, 11193]; prior 0; definite repeat True; native truth True

> Option 13 fragment 0: row [0,0,7,1,9]. 0->7? 0->2->4->7 or 0->2->5->7 exists. 1->9? 1->2->4->7->9 or 1->2->5->7->9 exists. Eligible.

- Episode 14: derive; F10; span [11195, 11372]; prior None; definite repeat False; native truth False

> Option 14 fragment 10: row [10,4,8,5,11]. 4->8? edges 4->7->9? 9->11 not 8. 4->7->9->11, no 8. Maybe 4->...->8? edges to 8: 6->8. 4->7 no to 6. So no path 4->8. Thus ineligible.

- Episode 15: derive; F3; span [19728, 19857]; prior None; definite repeat False; native truth True

> - F3: [0,11,3,9] paths 0->11 and 3->9. Edges: 0->2,2->4,4->7,7->9,9->11 so 0->11 exists. 3->6,6->8,8->9 so 3->9 exists. Eligible.

- Episode 18: derive; F1; span [20029, 20119]; prior None; definite repeat False; native truth True

> - F1: [2,9,3,11] paths 2->9 and 3->11. 2->4->7->9 exists. 3->6->8->9->11 exists. Eligible.

- Episode 20: derive; F4; span [20236, 20342]; prior 11; definite repeat True; native truth True

> Also F4: [1,7,6,11] would need 1->7 (1->2->4->7 yes) and 6->11 (6->8->9->11 yes) eligible but not offered.

- Episode 21: derive; F4; span [24554, 24693]; prior 11; definite repeat True; native truth True

> Fragment 4: first 1→7, second 6→11.
> Path 1→7: 1→2→4→7. Yes (1-2, 2-4, 4-7).
> Path 6→11: 6→8→9→11. Yes (6-8, 8-9, 9-11).
> Fragment 4 eligible.

- Episode 22: derive; F6; span [24827, 24906]; prior 3; definite repeat True; native truth True

> Fragment 6: first 3→8, second 9→11.
> 3→8: 3→6→8. Yes.
> 9→11: 9→11. Yes.
> Eligible.

- Episode 23: derive; F0; span [24908, 25005]; prior 0; definite repeat True; native truth True

> Fragment 0: first 0→7, second 1→9.
> 0→7: 0→2→4→7? 0-2, 2-4, 4-7 yes.
> 1→9: 1→2→4→7→9 yes. Eligible.

- Episode 24: derive; F2; span [25007, 25088]; prior 1; definite repeat True; native truth True

> Fragment 2: first 4→11, second 5→9.
> 4→11: 4→7→9→11 yes.
> 5→9: 5→7→9 yes. Eligible.

- Episode 25: derive; F8; span [25090, 25342]; prior 4; definite repeat False; native truth False

> Fragment 8: first 0→8, second 1→7.
> 0→8: 0→2→4→7→9? no, need to reach 8. Path to 8: 6→8, or 8→9. Edges into 8: [6,8]. From 0: 0→2→4→7→9→11... no path to 6? Edges into 6: [3,6]. From 0 to 3? No edge to 3. So 0→8 no directed path. Fragment 8 not eligible.

Rejected labels retained:
[{"annotation":{"claim":"Fragment 5 eligible: paths 2->7 and 8->11 exist.","explanation":"Derives both required paths for fragment 5.","fragment":5,"kind":"derive","occurrence":0,"paths":[[2,7],[8,11]],"premiseEdges":[[2,4],[4,7],[8,9],[9,11]],"prior":null,"quote":"first path 2->7? 2->4->7 yes length 2 positive. 8->11? 8->9->11 yes length 2. eligible. (Option id 7)","ready":true},"failure":"quote not present verbatim","index":5},{"annotation":{"claim":"Fragment 5 eligible: paths 2->7 and 8->11 exist.","explanation":"New derivation of same fragment 5 conclusion from same source edges.","fragment":5,"kind":"derive","occurrence":0,"paths":[[2,7],[8,11]],"premiseEdges":[[2,4],[4,7],[8,9],[9,11]],"prior":5,"quote":"- F5: [2,7,8,11] paths 2->7 and 8->11. 2->4->7 exists. 8->9->11 exists. Eligible.","ready":true},"failure":"prior annotation was rejected","index":16},{"annotation":{"claim":"Fragment 7 eligible: paths 0->9 and 10->11 exist.","explanation":"New derivation of same fragment 7 conclusion; support for 0->9 is abbreviated but same source context.","fragment":7,"kind":"derive","occurrence":0,"paths":[[0,9],[10,11]],"premiseEdges":[[10,11]],"prior":7,"quote":"- F7: [0,9,10,11] paths 0->9 and 10->11. 0->...->9 exists. 10->11 edge exists. Eligible.","ready":true},"failure":"different conclusion/premise context","index":17},{"annotation":{"claim":"Fragment 11 ineligible because path 10->9 is absent.","explanation":"Repeats negative fragment 11 conclusion in a new branch context.","fragment":11,"kind":"derive","occurrence":0,"paths":[[10,9],[0,7]],"premiseEdges":[[10,11]],"prior":9,"quote":"- F11: [10,9,0,7] paths 10->9? edges from 10: 10->11 only. No 10->9. Not eligible. So option 19 likely ineligible.","ready":true},"failure":"different conclusion/premise context","index":19}]

## paid/branch-search-4-baseline-1

Text SHA `7a100a33731b179b2e30da29b5637d59d94f33df0fdfc04c0dbf3b39e34748a2`; annotation failure `None`.

- Episode 1: derive; F1; span [901, 1005]; prior None; definite repeat False; native truth False

> Option fragment2 (id1): first 2->11? second 5->9? Path 2->4->7->9->11 yes. second 5->7->9 yes. Eligible.

- Episode 2: derive; F2; span [1052, 1171]; prior None; definite repeat False; native truth False

> Option fragment4 (id2): first 1->7? second 6->11? Check 1->2->4->7 yes or 1->2->5->7. second 6->8->9->11 yes. Eligible.

- Episode 3: derive; F3; span [1173, 1256]; prior None; definite repeat False; native truth False

> Option fragment6 (id3): first 3->8? second 9->11? 3->6->8 yes. 9->11 yes. Eligible.

- Episode 4: derive; F4; span [1258, 1552]; prior None; definite repeat False; native truth False

> Option fragment8 (id4): first 0->8? second 1->7? Check 0->2... can 0 reach 8? 0->2->? edges to 4,5; 4->7;5->7; 7->9; 9->11; 8->9 only, no edge to 8 except 3->6->8. From 0 cannot reach 8? 0->2->4->7->9->11; no 8. 0->2->5->7->9->11. So first path 0->8 does not exist. Option fragment8 ineligible.

Rejected labels retained:
[{"annotation":{"claim":"Fragment 0 is eligible: directed paths 0 to 7 and 1 to 9 both exist.","explanation":"Explicit chain support for both required paths of fragment 0.","fragment":0,"kind":"derive","occurrence":0,"paths":[[0,7],[1,9]],"premiseEdges":[[0,2],[2,4],[4,7],[1,2],[2,5],[5,7],[7,9]],"prior":null,"quote":"Option fragment 0: first path from 0 to7, second from1 to9. Check directed paths:\n0->2->4->7 yes, or 0->2->5->7. second 1->2->4->7->9 yes or 1->2->5->7->9 yes. Eligible.","ready":true},"failure":"quote not present verbatim","index":0},{"annotation":{"claim":"Fragment 1 (option id1) is eligible: paths 2 to 11 and 5 to 9 exist.","explanation":"Replay of same source-bound conjunction with same support from call 0.","fragment":1,"kind":"derive","occurrence":1,"paths":[[2,11],[5,9]],"premiseEdges":[[2,4],[4,7],[7,9],[9,11],[5,7]],"prior":1,"quote":"Option fragment2 (id1): first 2->11? second 5->9? Path 2->4->7->9->11 yes. second 5->7->9 yes. Eligible.","ready":true},"failure":"quote not present verbatim","index":5},{"annotation":{"claim":"Fragment 2 (option id2) is eligible: paths 1 to 7 and 6 to 11 exist.","explanation":"Replay of same source-bound conjunction with same support.","fragment":2,"kind":"derive","occurrence":1,"paths":[[1,7],[6,11]],"premiseEdges":[[1,2],[2,4],[4,7],[6,8],[8,9],[9,11]],"prior":2,"quote":"Option fragment4 (id2): first 1->7? second 6->11? Check 1->2->4->7 yes or 1->2->5->7. second 6->8->9->11 yes. Eligible.","ready":true},"failure":"quote not present verbatim","index":6},{"annotation":{"claim":"Fragment 3 (option id3) is eligible: paths 3 to 8 and 9 to 11 exist.","explanation":"Replay of same source-bound conjunction with same support.","fragment":3,"kind":"derive","occurrence":1,"paths":[[3,8],[9,11]],"premiseEdges":[[3,6],[6,8],[9,11]],"prior":3,"quote":"Option fragment6 (id3): first 3->8? second 9->11? 3->6->8 yes. 9->11 yes. Eligible.","ready":true},"failure":"quote not present verbatim","index":7},{"annotation":{"claim":"Fragment 8 (option id4) is ineligible because no path 0 to 8 exists.","explanation":"Replay of the same source-bound negative deduction.","fragment":4,"kind":"derive","occurrence":1,"paths":[[0,8]],"premiseEdges":[[0,2],[2,4],[4,7],[7,9],[9,11],[2,5],[5,7]],"prior":4,"quote":"Option fragment0 (id4): first 0->8? second 1->7? Check 0->2... can 0 reach 8? 0->2->? edges to 4,5; 4->7;5->7; 7->9; 9->11; 8->9 only, no edge to 8 except 3->6->8. From 0 cannot reach 8? 0->2->4->7->9->11; no 8. 0->2->5->7->9->11. So first path 0->8 does not exist.","ready":true},"failure":"quote not present verbatim","index":8},{"annotation":{"claim":"Fragment 6 is eligible: directed paths 3 to 8 and 9 to 11 exist.","explanation":"Explicit chain support for both required paths of fragment 6.","fragment":6,"kind":"derive","occurrence":0,"paths":[[3,8],[9,11]],"premiseEdges":[[3,6],[6,8],[9,11]],"prior":null,"quote":"fragment 6: first 3->8? second 9->11? Check directed paths:\n3->8: 3->6->8 exists (3-6,6-8). Yes.\n9->11: edge 9->11 exists. Yes. Eligible.","ready":true},"failure":"quote not present verbatim","index":9},{"annotation":{"claim":"Fragment 0 is eligible: directed paths 0 to 7 and 1 to 9 exist.","explanation":"Explicit chain support for both required paths of fragment 0.","fragment":7,"kind":"derive","occurrence":0,"paths":[[0,7],[1,9]],"premiseEdges":[[0,2],[2,4],[4,7],[2,5],[5,7],[1,2],[7,9]],"prior":null,"quote":"fragment 0: first 0->7, second 1->9.\n0->7: 0->2, 2->4, 4->7 or 2->5->7. Yes.\n1->9: 1->2, 2->4/5 ->7->9. Yes. Eligible.","ready":true},"failure":"quote not present verbatim","index":10},{"annotation":{"claim":"Fragment 2 is eligible: directed paths 4 to 11 and 5 to 9 exist.","explanation":"Explicit chain support for both required paths of fragment 2.","fragment":10,"kind":"derive","occurrence":0,"paths":[[4,11],[5,9]],"premiseEdges":[[4,7],[7,9],[9,11],[5,7]],"prior":null,"quote":"fragment 2: first 4->11, second 5->9.\n4->11: 4->7->9->11. Yes.\n5->9: 5->7->9. Yes. Eligible.","ready":true},"failure":"quote not present verbatim","index":11},{"annotation":{"claim":"Fragment 10 is ineligible because no path 4 to 8 exists.","explanation":"Explicit negative reachability deduction excluding fragment 10.","fragment":13,"kind":"derive","occurrence":0,"paths":[[4,8]],"premiseEdges":[[4,7],[7,9],[9,11]],"prior":null,"quote":"fragment 10: first 4->8, second 5->11.\n4->8: 4->7->9? does 4->8 exist? Edges 4->7, 7->9, 9->11, no 8. 4->8 no path (4->7->9->11; no 8). Wait maybe through? 4->7, 7->9, 9->11 no 8. So first path 4->8 does not exist. Not eligible?","ready":true},"failure":"quote not present verbatim","index":12},{"annotation":{"claim":"Fragment 6 is eligible: directed paths 3 to 8 and 9 to 11 exist.","explanation":"Replay of same source-bound conjunction with same support.","fragment":6,"kind":"derive","occurrence":1,"paths":[[3,8],[9,11]],"premiseEdges":[[3,6],[6,8],[9,11]],"prior":10,"quote":"fragment 6: first 3->8? second 9->11? Check directed paths:\n3->8: 3->6->8 exists (3-6,6-8). Yes.\n9->11: edge 9->11 exists. Yes. Eligible.","ready":true},"failure":"quote not present verbatim","index":13},{"annotation":{"claim":"Fragment 0 is eligible: directed paths 0 to 7 and 1 to 9 exist.","explanation":"Replay of same source-bound conjunction with same support.","fragment":7,"kind":"derive","occurrence":1,"paths":[[0,7],[1,9]],"premiseEdges":[[0,2],[2,4],[4,7],[2,5],[5,7],[7,9]],"prior":11,"quote":"fragment 0: first 0->7, second 1->9.\n0->7: 0->2, 2->4, 4->7 or 2->5->7. Yes.\n1->9: 1->2, 2->4/5 ->7->9. Yes. Eligible.","ready":true},"failure":"quote not present verbatim","index":14},{"annotation":{"claim":"Fragment 2 is eligible: directed paths 4 to 11 and 5 to 9 exist.","explanation":"Replay of same source-bound conjunction with same support.","fragment":10,"kind":"derive","occurrence":1,"paths":[[4,11],[5,9]],"premiseEdges":[[4,7],[7,9],[9,11],[5,7]],"prior":12,"quote":"fragment 2: first 4->11, second 5->9.\n4->11: 4->7->9->11. Yes.\n5->9: 5->7->9. Yes. Eligible.","ready":true},"failure":"quote not present verbatim","index":15},{"annotation":{"claim":"Fragment 10 is ineligible because no path 4 to 8 exists.","explanation":"Replay of the same source-bound negative deduction.","fragment":13,"kind":"derive","occurrence":1,"paths":[[4,8]],"premiseEdges":[[4,7],[7,9],[9,11]],"prior":13,"quote":"fragment 10: first 4->8, second 5->11.\n4->8: 4->7->9? does 4->8 exist? Edges 4->7, 7->9, 9->11, no 8. 4->8 no path (4->7->9->11; no 8). Wait maybe through? 4->7, 7->9, 9->11 no 8. So first path 4->8 does not exist. Not eligible?","ready":true},"failure":"quote not present verbatim","index":16}]

## paid/branch-search-4-fresh-0

Text SHA `43f5a4d90d2a19dd2ec5f157eca8ca0e7f97281e9e71aa40dd45b6787592fb3f`; annotation failure `None`.

- Episode 0: derive; F0; span [347, 476]; prior None; definite repeat False; native truth True

> id0 fragment 0: needs [0,0,7,1,9] i.e. first path 0->7, second 1->9. Do paths exist? 0->2->4->7 yes. 1->2->5->7->9 yes. eligible.

- Episode 1: derive; F2; span [478, 566]; prior None; definite repeat False; native truth True

> id1 fragment 2: needs [2,4,11,5,9]. 4->11? 4->7->9->11 yes. 5->9? 5->7->9 yes. eligible.

- Episode 2: derive; F4; span [568, 673]; prior None; definite repeat False; native truth True

> id2 fragment 4: needs [4,1,7,6,11]. 1->7? 1->2->4->7 or 1->2->5->7 yes. 6->11? 6->8->9->11 yes. eligible.

- Episode 3: derive; F6; span [675, 750]; prior None; definite repeat False; native truth True

> id3 fragment 6: needs [6,3,8,9,11]. 3->8? 3->6->8 yes. 9->11 yes. eligible.

- Episode 4: derive; F8; span [943, 1095]; prior None; definite repeat False; native truth True

> No path 0 to 8 because node 8 only incoming from 6, and 6 incoming from 3 only, no path from 0 to3. So ineligible. Also 1->7 exists yes. So id4 invalid.

- Episode 5: mention; F1; span [2193, 2520]; prior None; definite repeat False; native truth False

> Fragment 1: need [1,2,9,3,11] → paths from 1 to 2 and 9 to 3? Wait needs columns: fragmentId, firstFrom, firstTo, secondFrom, secondTo. So fragment 1: firstFrom=2, firstTo=9, secondFrom=3, secondTo=11. Wait need row [1,2,9,3,11]: fragmentId=1, firstFrom=2, firstTo=9, secondFrom=3, secondTo=11. Need directed path 2→9 and 3→11.

- Episode 6: derive; F1; span [2522, 2628]; prior None; definite repeat False; native truth True

> Check edges: 2→9 path: 2→4→7→9? edges (2,4),(4,7),(7,9) yes exists. 3→11: 3→6→8→9→11 yes exists. Eligible.

- Episode 7: derive; F3; span [2630, 2838]; prior None; definite repeat False; native truth True

> Fragment 3: need row [3,0,11,3,9]: firstFrom=3? wait no: row [3,0,11,3,9] fragmentId=3, firstFrom=0, firstTo=11, secondFrom=3, secondTo=9. Paths 0→11 exists (via 0-2-4-7-9-11), 3→9 exists (3-6-8-9). Eligible.

- Episode 8: derive; F5; span [2840, 2969]; prior None; definite repeat False; native truth True

> Fragment 5: need [5,2,7,8,11]: firstFrom=2,firstTo=7, secondFrom=8,secondTo=11. 2→7 via 2-4-7 yes. 8→11 via 8-9-11 yes. Eligible.

- Episode 9: derive; F7; span [2971, 3082]; prior None; definite repeat False; native truth True

> Fragment 7: need [7,0,9,10,11]: firstFrom=0,firstTo=9, secondFrom=10,secondTo=11. 0→9 yes. 10→11 yes. Eligible.

- Episode 10: derive; F9; span [4586, 4656]; prior None; definite repeat False; native truth True

> Fragment 9: [9,3,7,2,9]. first 3→7: no path. second 2→9 ✓. Ineligible.

- Episode 11: derive; F2; span [7245, 7479]; prior 1; definite repeat True; native truth True

> option 10 fragment 2. Need needs row fragment 2: [2,4,11,5,9] meaning first path 4->11? second 5->9. Need both directed paths exist. From source edges, path 4->11 exists? Edges 4->7,7->9,9->11 yes. 5->9 exists 5->7,7->9 yes. Eligible.

- Episode 13: derive; F6; span [7598, 7680]; prior 3; definite repeat True; native truth True

> option 12 fragment 6 need [6,3,8,9,11]: 3->8 yes (3->6,6->8); 9->11 yes. Eligible.

- Episode 15: derive; F10; span [7778, 7954]; prior None; definite repeat False; native truth True

> option14 fragment10 need [10,4,8,5,11]: 4->8? edges 4->7,7->9,8? no edge to 8. Actually 6->8, but 4 to 8: 4->7->9->? no 8; 7->9, 9->11, 10->11. There is no 4->8. so ineligible?

- Episode 16: mention; F4; span [23747, 23881]; prior None; definite repeat False; native truth False

> opts:
> 20 frag4 cost3 risk5 stage4 values [17,41], prefixTotals cost25 depth5 risk28 value208, seedSuffix cost37 depth7 risk39 value291

- Episode 19: derive; F6; span [25673, 25746]; prior 3; definite repeat True; native truth True

> Fragment 6: 3->8 and 9->11. 3->8: 3->6->8 yes. 9->11: edge yes. Eligible.

- Episode 20: derive; F2; span [25748, 25828]; prior 1; definite repeat True; native truth True

> Fragment 2: 4->11 and 5->9. 4->11: 4->7->9->11 yes. 5->9: 5->7->9 yes. Eligible.

- Episode 27: derive; F6; span [50807, 50994]; prior 3; definite repeat True; native truth True

> Fragment 6 need: [6,3,8,9,11] i.e first path 3→8, second path 9→11. Source edges: edges [3,6],[6,8] gives path 3→6→8 (positive length). Edge [9,11] gives path 9→11. So fragment6 eligible.

- Episode 29: derive; F2; span [51461, 51588]; prior 1; definite repeat True; native truth True

> Fragment 2 need: [2,4,11,5,9] first 4→11, second 5→9. Path 4→7→9→11? Edges 4→7,7→9,9→11 yes 4→11. Path 5→7→9 yes 5→9. Eligible.

- Episode 30: derive; F10; span [52770, 52940]; prior 15; definite repeat True; native truth True

> Fragment 10: 4->8? 4->7->9->8? no edge 9->8. 4->...->8: 4->7->9->11 no. 4->7? 7->9, 9->11. To reach 8 must come from 6->8. 4->7 doesn't reach 6. So 4->8 no. Not eligible.

- Episode 31: derive; F6; span [57684, 57966]; prior 3; definite repeat True; native truth True

> Eligibility: fragment 6 needs [6,3,8,9,11] from source needs row: [6,3,8,9,11]. Both positive-length directed paths: 3->8 and 9->11? Need source edges:
> 3->6, 6->8, so path 3 to 8 exists via 6 (edges [3,6],[6,8]).
> 9->11 exists edge [9,11].
> So fragment 6 eligible. Option 30 eligible.

- Episode 33: derive; F2; span [58201, 58310]; prior 1; definite repeat True; native truth True

> Option 32 fragment2 needs [2,4,11,5,9]. Path 4->11 exists? 4->7->9->11 yes. Path 5->9? 5->7->9 yes. eligible.

- Episode 34: derive; F10; span [58312, 58539]; prior 15; definite repeat True; native truth True

> Option 34 fragment10 needs [10,4,8,5,11]. Path 4->8? edges 4->7? 7->9, no 9->11; 8? no. Need path 4 to 8: 4->7->9, no 8. There is 6->8 but no from 7 to 6/3? 4->7, 5->7, no. 4->? only 4,7. 7->9. no 8. So fragment10 not eligible?

Rejected labels retained:
[{"annotation":{"claim":"Fragment 4 paths 1->7 and 6->11 both exist, so eligible.","explanation":"Re-derives fragment 4 eligibility from same required paths and edge chains in new call; duplicate derivation.","fragment":4,"kind":"derive","occurrence":0,"paths":[[1,7],[6,11]],"premiseEdges":[[1,2],[2,4],[4,7],[6,8],[8,9],[9,11]],"prior":2,"quote":"option 11 fragment 4 need [4,1,7,6,11]: paths 1->7? edges 1->2,2->4,4->7 yes. 6->11? 6->8,8->9,9->11 yes. Eligible.","ready":true},"failure":"different conclusion/premise context","index":12},{"annotation":{"claim":"Fragment 0 paths 0->7 and 1->9 both exist, so eligible.","explanation":"Re-derivation of fragment 0 eligibility with same paths and same source edges; distinct from earlier alternate 1->9 witness but same source-bound qualification.","fragment":0,"kind":"derive","occurrence":0,"paths":[[0,7],[1,9]],"premiseEdges":[[0,2],[2,4],[4,7],[1,2],[7,9]],"prior":0,"quote":"option13 fragment0 need [0,0,7,1,9]: 0->7 yes (0->2->4->7); 1->9? 1->2->4->7->9 yes. Eligible.","ready":true},"failure":"different conclusion/premise context","index":14},{"annotation":{"claim":"Fragment 4 paths 1->7 and 6->11 exist, so eligible.","explanation":"Same fragment 4 eligibility derivation with same ordered edges as earlier; duplicate source-bound deduction.","fragment":4,"kind":"derive","occurrence":0,"paths":[[1,7],[6,11]],"premiseEdges":[[1,2],[2,4],[4,7],[6,8],[8,9],[9,11]],"prior":2,"quote":"Fragment 4: 1->7 and 6->11. 1->7: 1->2->4->7 yes. 6->11: 6->8->9->11 yes. Eligible.","ready":true},"failure":"different conclusion/premise context","index":17},{"annotation":{"claim":"Fragment 0 paths 0->7 and 1->9 exist, so eligible.","explanation":"Same fragment 0 eligibility derivation from same paths and source edges; duplicate.","fragment":0,"kind":"derive","occurrence":0,"paths":[[0,7],[1,9]],"premiseEdges":[[0,2],[2,4],[4,7],[1,2],[7,9]],"prior":0,"quote":"Fragment 0: 0->7 and 1->9. 0->7: 0->2->4->7 exists. 1->9: 1->2->4->7->9 exists. Eligible yes.","ready":true},"failure":"different conclusion/premise context","index":18},{"annotation":{"claim":"Fragment 8 requires paths 0->8 and 1->7; 0->8 does not exist, so ineligible.","explanation":"Same negative fragment 8 eligibility deduction as earlier source-bound context; duplicate.","fragment":8,"kind":"derive","occurrence":0,"paths":[[0,8],[1,7]],"premiseEdges":[],"prior":4,"quote":"Fragment 8: 0->8 and 1->7. 0->8: 0->2->4->7->9? 9->? no 8. 0->2->4->7, 7->9, 9->11, not 8. 0->2->5->7->9; no. 0->2->4->7->9 no 8. So 0->8 does NOT exist. Thus fragment 8 ineligible.","ready":false},"failure":"different conclusion/premise context","index":21},{"annotation":{"claim":"Fragment 5 paths 2->7 and 8->11 exist, so eligible.","explanation":"Re-derives fragment 5 eligibility with same required paths; alternate 2->7 witness but same qualification.","fragment":5,"kind":"derive","occurrence":0,"paths":[[2,7],[8,11]],"premiseEdges":[[2,4],[4,7],[2,5],[5,7],[8,9],[9,11]],"prior":7,"quote":"Fragment 5: 2->7 exists (2->4->7 or 2->5->7) yes. 8->11? 8->9->11 yes. eligible.","ready":true},"failure":"different conclusion/premise context","index":22},{"annotation":{"claim":"Fragment 7 paths 0->9 and 10->11 both exist, so eligible.","explanation":"Same fragment 7 eligibility derivation from same paths and edges; duplicate.","fragment":7,"kind":"derive","occurrence":0,"paths":[[0,9],[10,11]],"premiseEdges":[[0,2],[2,4],[4,7],[7,9],[10,11]],"prior":8,"quote":"Fragment7: 0->9? 0->2->4->7->9 yes. 10->11 yes. eligible.","ready":true},"failure":"different conclusion/premise context","index":23},{"annotation":{"claim":"Fragment 1 paths 2->9 and 3->11 both exist, so eligible.","explanation":"Same fragment 1 eligibility derivation; duplicate.","fragment":1,"kind":"derive","occurrence":0,"paths":[[2,9],[3,11]],"premiseEdges":[[2,4],[4,7],[7,9],[3,6],[6,8],[8,9],[9,11]],"prior":5,"quote":"Fragment1: 2->9? 2->4->7->9 yes. 3->11? 3->6->8->9->11 yes. eligible.","ready":true},"failure":"repeat link must connect derivations","index":24},{"annotation":{"claim":"Fragment 3 paths 0->11 and 3->9 both exist, so eligible.","explanation":"Same fragment 3 eligibility derivation; duplicate.","fragment":3,"kind":"derive","occurrence":0,"paths":[[0,11],[3,9]],"premiseEdges":[[0,2],[2,4],[4,7],[7,9],[9,11],[3,6],[6,8],[8,9]],"prior":6,"quote":"Fragment3: 0->11? 0->2->4->7->9->11 yes. 3->9? 3->6->8->9 yes. eligible.","ready":true},"failure":"different conclusion/premise context","index":25},{"annotation":{"claim":"Fragment 9 requires paths 3->7 and 2->9; 3->7 unavailable, so ineligible.","explanation":"Same negative fragment 9 deduction as earlier; duplicate.","fragment":9,"kind":"derive","occurrence":0,"paths":[[3,7],[2,9]],"premiseEdges":[],"prior":9,"quote":"Fragment9: 3->7? 3->6->8->9? wait 3->6->8->9, then 7? no edge 9->7. also 3->6->8->9; no 8->? 7. Edges to 7: 4->7,5->7. From 3 only 3->6->8->9. no 3->7. So fragment9 ineligible? Need 3->7 unavailable.","ready":false},"failure":"different conclusion/premise context","index":26},{"annotation":{"claim":"Fragment 0 paths 0->7 and 1->9 exist, so eligible.","explanation":"Duplicate fragment 0 eligibility with same required paths and edges.","fragment":0,"kind":"derive","occurrence":0,"paths":[[0,7],[1,9]],"premiseEdges":[[0,2],[2,4],[4,7],[1,2],[7,9]],"prior":0,"quote":"Fragment 0 need: [0,0,7,1,9] first path 0→7, second 1→9. Source edges: 0→2→4→7 (edges 0,2;2,4;4,7) yes path 0→7. 1→2→4→7→9 or 1→2→5→7→9? First path 1→9 yes via 1,2 then 2,4,4,7,7,9 = 1→2→4→7→9. Eligible.","ready":true},"failure":"different conclusion/premise context","index":28},{"annotation":{"claim":"Fragment 0 paths 0->7 and 1->9 exist, so eligible.","explanation":"Duplicate fragment 0 derivation.","fragment":0,"kind":"derive","occurrence":0,"paths":[[0,7],[1,9]],"premiseEdges":[[0,2],[2,4],[4,7],[1,2],[7,9]],"prior":0,"quote":"Option 31 fragment0 needs [0,0,7,1,9]? Source needs [0,0,7,1,9] (fragmentId 0, firstFrom 0 firstTo7, secondFrom1 secondTo9). Path 0->7 exists? Edges: 0->2,2->4,4->7 yes (0-2-4-7). Path 1->9? edges 1->2,2->4,4->7,7->9 yes. eligible.","ready":true},"failure":"different conclusion/premise context","index":32}]

## paid/branch-search-4-fresh-1

Text SHA `ea78ef05a772b64e7f8ac508608f04f2862bb223492ef1813b40213369560c47`; annotation failure `None`.

- Episode 0: derive; F0; span [1177, 1321]; prior None; definite repeat False; native truth True

> Fragment 0 needs path 0->7 and 1->9.
> 0->7: 0->2->4->7 exists yes (path node 47). 1->9: 1->2->4->7->9 or 1->2->5->7->9 exists yes (57). Eligible.

- Episode 1: derive; F2; span [1323, 1414]; prior None; definite repeat False; native truth True

> Fragment 2 needs 4->11 and 5->9.
> 4->11: 4->7->9->11 exists. 5->9: 5->7->9 exists. Eligible.

- Episode 2: derive; F4; span [1416, 1524]; prior None; definite repeat False; native truth True

> Fragment 4 needs 1->7 and 6->11.
> 1->7: 1->2->4->7 or 1->2->5->7 exists. 6->11: 6->8->9->11 exists. Eligible.

- Episode 3: derive; F6; span [1526, 1616]; prior None; definite repeat False; native truth True

> Fragment 6 needs 3->8 and 9->11.
> 3->8: 3->6->8 exists. 9->11: edge 9->11 exists. Eligible.

- Episode 4: uncertain; F8; span [1618, 1696]; prior None; definite repeat False; native truth False

> Fragment 8 needs 0->8 and 1->7.
> 0->8: is there path 0->2->4->7->9 ... no to 8?

- Episode 5: derive; F8; span [1820, 1866]; prior None; definite repeat False; native truth True

> So 0->8 NOT exist. Thus fragment 8 ineligible.

- Episode 10: mention; F3; span [4833, 4872]; prior None; definite repeat False; native truth False

> fragment 3: [3,0,11,3,9] => 0->11, 3->9

- Episode 19: derive; F1; span [5288, 5383]; prior None; definite repeat False; native truth True

> Option id5 fragment1: need 2->9 and 3->11. 2->4->7->9 yes. 3->6->8->9->11 yes. Eligible likely.

- Episode 20: derive; F3; span [5385, 5476]; prior None; definite repeat False; native truth True

> Option id6 fragment3: need 0->11 and 3->9. 0->2->4->7->9->11 yes; 3->6->8->9 yes. Eligible.

- Episode 21: derive; F5; span [5478, 5570]; prior None; definite repeat False; native truth True

> Option id7 fragment5: need 2->7 and 8->11. 2->4->7 yes (or 2->5->7); 8->9->11 yes. Eligible.

- Episode 22: derive; F7; span [5572, 5661]; prior None; definite repeat False; native truth True

> Option id8 fragment7: need 0->9 and 10->11. 0->2->4->7->9 yes; 10->11 edge yes. Eligible.

- Episode 23: derive; F9; span [5663, 5843]; prior None; definite repeat False; native truth True

> Option id9 fragment9: need 3->7 and 2->9. 3->6->8->9 but no to 7? 3->6->8->9; no edge to 7. Path 3->...? 3->6->8->9, 9->11, no 7. So 3->7 does NOT exist. Thus fragment9 ineligible.

- Episode 24: derive; F2; span [7784, 8095]; prior None; definite repeat False; native truth True

> - option 10 fragment 2: need row 2: first (4 ->11), second (5->9). Need both paths exist in source edges. Source edges as list: [0,2],[1,2],[2,4],[2,5],[4,7],[5,7],[3,6],[6,8],[7,9],[8,9],[9,11],[10,11]. Directed paths positive length. Need path 4 to 11 and 5 to 9. Check 4->7->9->11 yes. 5->7->9 yes. Eligible.

- Episode 25: derive; F4; span [8096, 8275]; prior None; definite repeat False; native truth True

> - option 11 fragment 4: need row4: [4,1,7,6,11] first 1->7, second 6->11. Source edges: 1->2->4->7 yes (1,2,4,7) or 1->2->5->7; 6->8->9->11? Edges 6->8, 8->9, 9->11 yes. Eligible.

- Episode 26: derive; F6; span [8276, 8383]; prior None; definite repeat False; native truth True

> - option 12 fragment 6: need row6: [6,3,8,9,11] first 3->8, second 9->11. 3->6->8 yes; 9->11 yes. Eligible.

- Episode 27: derive; F0; span [8384, 8531]; prior None; definite repeat False; native truth True

> - option 13 fragment 0: need row0: [0,0,7,1,9] first 0->7, second 1->9. 0->2->4->7 or 0->2->5->7 yes. 1->2->4->7->9 or 1->2->5->7->9 yes. Eligible.

- Episode 28: derive; F10; span [8532, 8871]; prior None; definite repeat False; native truth True

> - option 14 fragment 10: need row10: [10,4,8,5,11] first 4->8, second 5->11. 4->7->9? no edge to 8? 4->7->9->11, but 4->8? Paths: 4->7->9, 9->11, no 8. There is no path 4 to 8 because edges: 4->7, 7->9, 8->9, 6->8. 8 only from 6; 4 to 6? 4->7->9, no 6. So first path 4->8 does not exist. Fragment 10 ineligible. So cannot choose option 14.

- Episode 29: reuse; F3; span [12276, 12390]; prior None; definite repeat False; native truth True

> Fragment 3: [3,0,11,3,9] => need path 0->11 and 3->9. Evidence has path 0->11 (node 62), path 3->9 (52). Eligible.

- Episode 30: reuse; F5; span [12392, 12487]; prior None; definite repeat False; native truth True

> Fragment 5: [5,2,7,8,11] => need 2->7 and 8->11. Evidence path 2->7 (40), 8->11 (46). Eligible.

- Episode 31: reuse; F7; span [12489, 12556]; prior None; definite repeat False; native truth True

> Fragment 7: [7,0,9,10,11] => need 0->9 (56), 10->11 (35). Eligible.

- Episode 32: reuse; F1; span [12558, 12623]; prior None; definite repeat False; native truth True

> Fragment 1: [1,2,9,3,11] => need 2->9 (49), 3->11 (59). Eligible.

- Episode 33: derive; F11; span [12625, 12812]; prior None; definite repeat False; native truth True

> Fragment 11: [11,10,9,0,7] => need 10->9 and 0->7. Is there path 10->9? source edges: 10->11, ... no 10->9. Need check evidence path? There is no [10,9] path. So fragment 11 not eligible.

- Episode 34: derive; F4; span [17168, 17259]; prior 2; definite repeat True; native truth True

> Fragment 4: row [4,1,7,6,11]: 1->7? Edges 1->2->4->7 yes. 6->11? 6->8->9->11 yes. Eligible.

- Episode 38: derive; F8; span [17331, 17565]; prior None; definite repeat False; native truth True

> Fragment 8: row [8,0,8,1,7]: 0->8? 0->2->4->7->9->? no to 8? Edges: 7->9,9->11, 6->8, 8->9. 0->? to 6? no. 0->2->5->7->9, no 8. So path 0->8 may not exist. Need both. 1->7 yes. Fragment8 not eligible due 0->8 no path. So exclude id24.

- Episode 40: derive; F5; span [20394, 20532]; prior None; definite repeat False; native truth True

> firstFrom=2 firstTo=7 path exists? Source edges include 2->4->7 yes path [2,4,7]. secondFrom=8 secondTo=11 path 8->9->11 yes. So eligible.

- Episode 42: derive; F6; span [26701, 26796]; prior None; definite repeat False; native truth True

> Option 30 fragment 6: need paths 3->8 and 9->11. 3->6->8 exists. 9->11 direct exists. Eligible.

- Episode 43: derive; F0; span [26798, 26910]; prior None; definite repeat False; native truth True

> Option 31 fragment 0: 0->7 exists via 0->2->4->7 or 0->2->5->7. 1->9: 1->2->4->7->9 or via 2->5->7->9. eligible.

- Episode 44: derive; F2; span [26912, 26990]; prior None; definite repeat False; native truth True

> Option 32 fragment 2: 4->11 exists 4->7->9->11. 5->9 exists 5->7->9. eligible.

- Episode 45: derive; F4; span [26992, 27083]; prior None; definite repeat False; native truth True

> Option 33 fragment 4: 1->7 exists 1->2->4->7 (or 5->7); 6->11 exists 6->8->9->11. eligible.

- Episode 46: derive; F10; span [27085, 27342]; prior None; definite repeat False; native truth True

> Option 34 fragment 10: 4->8? Edges: 4->7->9->8? no, edge 8->9 oriented 8->9, not 9->8. 4 to 8: 4->7->9->11? no 11 no outgoing. Could there be 4->7->9->8 no. 4->? 4->7 only, 7->9, 9->11. No path to 8. So fragment 10 ineligible (unless path 4->...->8 absent).

Rejected labels retained:
[{"annotation":{"claim":"Ineligible fragment 8 option should not be chosen.","explanation":"Reuses the prior F8 ineligibility finding.","fragment":8,"kind":"reuse","occurrence":0,"paths":[[0,8],[1,7]],"premiseEdges":[],"prior":null,"quote":"Option id4 should not choose.","ready":null},"failure":"quote not present verbatim","index":6},{"annotation":{"claim":"Fragment 0 requires paths 0→7 and 1→9.","explanation":"Lists F0 need paths, no inference.","fragment":0,"kind":"mention","occurrence":1,"paths":[[0,7],[1,9]],"premiseEdges":[],"prior":null,"quote":"fragment 0: [0,0,7,1,9] => paths 0->7, 1->9","ready":null},"failure":"quote not present verbatim","index":7},{"annotation":{"claim":"Fragment 1 requires paths 2→9 and 3→11.","explanation":"Lists F1 need paths, no inference.","fragment":1,"kind":"mention","occurrence":1,"paths":[[2,9],[3,11]],"premiseEdges":[],"prior":null,"quote":"fragment 1: [1,2,9,3,11] => 2->9, 3->11","ready":null},"failure":"quote not present verbatim","index":8},{"annotation":{"claim":"Fragment 2 requires paths 4→11 and 5→9.","explanation":"Lists F2 need paths, no inference.","fragment":2,"kind":"mention","occurrence":1,"paths":[[4,11],[5,9]],"premiseEdges":[],"prior":null,"quote":"fragment 2: [2,4,11,5,9] => 4->11, 5->9","ready":null},"failure":"quote not present verbatim","index":9},{"annotation":{"claim":"Fragment 4 requires paths 1→7 and 6→11.","explanation":"Lists F4 need paths, no inference.","fragment":4,"kind":"mention","occurrence":1,"paths":[[1,7],[6,11]],"premiseEdges":[],"prior":null,"quote":"fragment 4: [4,1,7,6,11] => 1->7, 6->11","ready":null},"failure":"quote not present verbatim","index":11},{"annotation":{"claim":"Fragment 5 requires paths 2→7 and 8→11.","explanation":"Lists F5 need paths, no inference.","fragment":5,"kind":"mention","occurrence":1,"paths":[[2,7],[8,11]],"premiseEdges":[],"prior":null,"quote":"fragment 5: [5,2,7,8,11] => 2->7, 8->11","ready":null},"failure":"quote not present verbatim","index":12},{"annotation":{"claim":"Fragment 6 requires paths 3→8 and 9→11.","explanation":"Lists F6 need paths, no inference.","fragment":6,"kind":"mention","occurrence":1,"paths":[[3,8],[9,11]],"premiseEdges":[],"prior":null,"quote":"fragment 6: [6,3,8,9,11] => 3->8, 9->11","ready":null},"failure":"quote not present verbatim","index":13},{"annotation":{"claim":"Fragment 7 requires paths 0→9 and 10→11.","explanation":"Lists F7 need paths, no inference.","fragment":7,"kind":"mention","occurrence":1,"paths":[[0,9],[10,11]],"premiseEdges":[],"prior":null,"quote":"fragment 7: [7,0,9,10,11] => 0->9, 10->11","ready":null},"failure":"quote not present verbatim","index":14},{"annotation":{"claim":"Fragment 8 requires paths 0→8 and 1→7.","explanation":"Lists F8 need paths, no inference.","fragment":8,"kind":"mention","occurrence":1,"paths":[[0,8],[1,7]],"premiseEdges":[],"prior":null,"quote":"fragment 8: [8,0,8,1,7] => 0->8, 1->7","ready":null},"failure":"quote not present verbatim","index":15},{"annotation":{"claim":"Fragment 9 requires paths 3→7 and 2→9.","explanation":"Lists F9 need paths, no inference.","fragment":9,"kind":"mention","occurrence":1,"paths":[[3,7],[2,9]],"premiseEdges":[],"prior":null,"quote":"fragment 9: [9,3,7,2,9] => 3->7, 2->9","ready":null},"failure":"quote not present verbatim","index":16},{"annotation":{"claim":"Fragment 10 requires paths 4→8 and 5→11.","explanation":"Lists F10 need paths, no inference.","fragment":10,"kind":"mention","occurrence":1,"paths":[[4,8],[5,11]],"premiseEdges":[],"prior":null,"quote":"fragment 10: [10,4,8,5,11] => 4->8, 5->11","ready":null},"failure":"quote not present verbatim","index":17},{"annotation":{"claim":"Fragment 11 requires paths 10→9 and 0→7.","explanation":"Lists F11 need paths, no inference.","fragment":11,"kind":"mention","occurrence":1,"paths":[[10,9],[0,7]],"premiseEdges":[],"prior":null,"quote":"fragment 11: [11,10,9,0,7] => 10->9, 0->7","ready":null},"failure":"quote not present verbatim","index":18},{"annotation":{"claim":"Fragment 0 satisfies both required directed paths 0→7 and 1→9.","explanation":"Same F0 readiness derivation from same edge chain in new call context.","fragment":0,"kind":"derive","occurrence":0,"paths":[[0,7],[1,9]],"premiseEdges":[[0,2],[2,4],[4,7],[1,2],[7,9]],"prior":1,"quote":"Fragment 0: need [0,0,7,1,9]: paths 0->7 and 1->9. Source edges: from evidence derivation there is path 0->7? Yes node 47 path [0,7] via edges 0-2,2-4,4-7? Wait source edges include [0,2],[2,4],[4,7], yes. 1->9? path 1->2->4->7->9? edges [1,2],[2,4],[4,7],[7,9] yes. Eligible. But check option id22 fragment0 values [29,38]? likely paths ids? Need not.","ready":true},"failure":"out of chronological order","index":35},{"annotation":{"claim":"Fragment 2 satisfies both required directed paths 4→11 and 5→9.","explanation":"Same F2 readiness derivation from same edge chain in new call context.","fragment":2,"kind":"derive","occurrence":0,"paths":[[4,11],[5,9]],"premiseEdges":[[4,7],[7,9],[9,11],[5,7]],"prior":1,"quote":"Fragment 2: need row [2,4,11,5,9]: paths 4->11 and 5->9. Edges: 4->7->9->11 yes; 5->7->9 yes. Eligible.","ready":true},"failure":"out of chronological order","index":36},{"annotation":{"claim":"Fragment 6 satisfies both required directed paths 3→8 and 9→11.","explanation":"Same F6 readiness derivation from same edge chain in new call context.","fragment":6,"kind":"derive","occurrence":0,"paths":[[3,8],[9,11]],"premiseEdges":[[3,6],[6,8],[9,11]],"prior":2,"quote":"Fragment 6: row [6,3,8,9,11]: 3->8 yes 3->6->8; 9->11 yes. Eligible.","ready":true},"failure":"different conclusion/premise context","index":37},{"annotation":{"claim":"Eligibility requires both directed paths for a fragment's need to exist in source edges.","explanation":"General eligibility rule mention.","fragment":null,"kind":"mention","occurrence":0,"paths":[],"premiseEdges":[],"prior":null,"quote":"Need check fragment eligibility by paths of fragment F exist in source edges. The source needs define for each fragment two directed paths:","ready":null},"failure":"out of chronological order","index":39},{"annotation":{"claim":"Fragment 9 is ineligible because path 3→7 does not exist.","explanation":"Negative eligibility conclusion for F9.","fragment":9,"kind":"derive","occurrence":0,"paths":[[3,7],[2,9]],"premiseEdges":[],"prior":null,"quote":"Fragment 9: need [9,3,7,2,9]: 3->7? Wait need [9,3,7,2,9], so fragment 9: firstFrom 3 firstTo 7. Is there directed path 3->7? Edges: 3->6->8->9, and 2->4->7. No path from 3 to7. So ineligible.","ready":false},"failure":"quote not present verbatim","index":41}]

## paid/branch-search-4-retained-0

Text SHA `a1438cc538196b453c0f54b23c0ff11592435976255561ad3c147f38b20ad515`; annotation failure `None`.

- Episode 0: derive; F0; span [697, 826]; prior None; definite repeat False; native truth True

> Option 0 fragment 0 need [0,0,7,1,9]. Need path 0->7 exists? edges: 0->2->4->7 yes. Path 1->9? edges 1->2->4->7->9 yes. Eligible.

- Episode 1: derive; F2; span [827, 923]; prior None; definite repeat False; native truth True

> Option 1 fragment 2 need [2,4,11,5,9]. Need 4->11? 4->7->9->11 yes. 5->9? 5->7->9 yes. Eligible.

- Episode 2: derive; F4; span [924, 1023]; prior None; definite repeat False; native truth True

> Option 2 fragment 4 need [4,1,7,6,11]. Need 1->7? 1->2->4->7 yes. 6->11? 6->8->9->11 yes. Eligible.

- Episode 3: derive; F6; span [1024, 1107]; prior None; definite repeat False; native truth True

> Option 3 fragment 6 need [6,3,8,9,11]. Need 3->8? 3->6->8 yes. 9->11 yes. Eligible.

- Episode 4: derive; F8; span [1108, 1302]; prior None; definite repeat False; native truth False

> Option 4 fragment 8 need [8,0,8,1,7]. Need 0->8? 0->2->4->7? no 7->? 7->9->11, no 8. 0->2->5->7->9... no 8. There is edge 6->8 only, 3->6->8. So 0->8 absent. Thus option 4 fragment 8 ineligible?

- Episode 5: derive; F8; span [3543, 3682]; prior None; definite repeat False; native truth False

> Could option 4 be eligible if path 0->8 maybe via 0->2->5->7? no 7->9->11 not 8. 0->2->4->7->? no. No edge to 8 except 6->8. So ineligible.

- Episode 7: derive; F1; span [4742, 4924]; prior None; definite repeat False; native truth True

> Fragment 1 need: [1,2,9,3,11] firstFrom 2 firstTo9, secondFrom3 secondTo11. Are there paths 2→9 and 3→11? Edges: 2-4-7-9 yes 2→9. 3-6-8-9-11 yes 3→11. Both positive length. Eligible.

- Episode 8: derive; F3; span [4926, 5039]; prior None; definite repeat False; native truth True

> Fragment 3: need [3,0,11,3,9] paths 0→11 and 3→9. 0→11 exists (0-2-5-7-9-11 etc). 3→9 exists (3-6-8-9). Eligible.

- Episode 9: derive; F5; span [5041, 5130]; prior None; definite repeat False; native truth True

> Fragment 5: need [5,2,7,8,11] 2→7 and 8→11. 2→7 yes (2-4-7). 8→11 yes (8-9-11). Eligible.

- Episode 10: derive; F7; span [5132, 5215]; prior None; definite repeat False; native truth True

> Fragment 7: [7,0,9,10,11] 0→9 and 10→11. 0→9 yes. 10→11 yes (edge 10-11). Eligible.

- Episode 11: derive; F9; span [5217, 5343]; prior None; definite repeat False; native truth False

> Fragment 9: [9,3,7,2,9] 3→7 and 2→9. 3→7? 3-6-8-9... no 7. Edges from 3 only to 6, 6→8, 8→9, 9→11. So no path 3→7. Ineligible.

- Episode 12: derive; F4; span [29762, 30104]; prior None; definite repeat False; native truth True

> Source needs rows: needs has fragmentId, firstFrom, firstTo, secondFrom, secondTo. For option fragment 4, need row [4,1,7,6,11] from source needs. Both positive-length directed paths: from 1 to7 and from 6 to11 must exist in source edges. Source edges includes 1->2, 2->5, 5->7 (path 1 to7 yes). 6->8, 8->9, 9->11 (path 6 to11 yes). Eligible.

- Episode 29: reuse; F1; span [39887, 39958]; prior None; definite repeat False; native truth True

> fragment 1: [1,2,9,3,11] → 2→9 path exists (F49), 3→11 (F59). Eligible.

- Episode 30: reuse; F2; span [39959, 40018]; prior None; definite repeat False; native truth True

> fragment 2: [2,4,11,5,9] → 4→11 (F50), 5→9 (F42). Eligible.

- Episode 31: reuse; F3; span [40019, 40078]; prior None; definite repeat False; native truth True

> fragment 3: [3,0,11,3,9] → 0→11 (F62), 3→9 (F52). Eligible.

- Episode 32: reuse; F4; span [40079, 40138]; prior None; definite repeat False; native truth True

> fragment 4: [4,1,7,6,11] → 1→7 (F48), 6→11 (F53). Eligible.

- Episode 33: reuse; F5; span [40139, 40198]; prior None; definite repeat False; native truth True

> fragment 5: [5,2,7,8,11] → 2→7 (F40), 8→11 (F46). Eligible.

- Episode 34: reuse; F6; span [40199, 40258]; prior None; definite repeat False; native truth True

> fragment 6: [6,3,8,9,11] → 3→8 (F43), 9→11 (F34). Eligible.

- Episode 35: reuse; F7; span [40259, 40320]; prior None; definite repeat False; native truth True

> fragment 7: [7,0,9,10,11] → 0→9 (F56), 10→11 (F35). Eligible.

- Episode 36: derive; F6; span [48759, 48965]; prior None; definite repeat False; native truth True

> Check eligibility for each option.
> 
> Option 30: fragment 6, needs 3->8 and 9->11. Edges: 3->6, 6->8 exists (node 6 "source edge [3,6]" and [6,8]). So 3->8 exists. 9->11 exists ([9,11]). Both exist. Eligible.

- Episode 37: derive; F0; span [48983, 49077]; prior None; definite repeat False; native truth True

> Option 31: fragment 0, needs 0->7 and 1->9. 0->2->4->7 exists. 1->2->4->7->9 exists. Eligible.

- Episode 38: derive; F2; span [49096, 49186]; prior None; definite repeat False; native truth True

> Option 32: fragment 2, needs 4->11 and 5->9. 4->7->9->11 exists. 5->7->9 exists. Eligible.

- Episode 43: derive; FNone; span [62822, 62958]; prior None; definite repeat False; native truth False

> Path 4->8? Need directed paths in source edges from 4 to 8. Edges: 4->7->9->11, and 6->8, 3->6. No way to reach 8 from 4. So ineligible.

Rejected labels retained:
[{"annotation":{"claim":"Fragment 4 eligibility re-derived: 1→7 via 1→2→4→7 and 6→11 via 6→8→9→11.","explanation":"Same conclusion and same ordered direct edges as earlier F4 derivation in same call; this is a textual re-derivation episode.","fragment":4,"kind":"derive","occurrence":0,"paths":[[1,7],[6,11]],"premiseEdges":[[1,2],[2,4],[4,7],[6,8],[8,9],[9,11]],"prior":null,"quote":"Best eligible seems id2 fragment4: cost5 risk5 value36, total cost44 risk33 value211. Need check fragment 4 paths: need [4,1,7,6,11]. Path 1->7: 1->2->4->7 (yes). 6->11: 6->8->9->11 (yes). Both positive-length. Eligible.","ready":true},"failure":"quote not present verbatim","index":6},{"annotation":{"claim":"Fragment 2 eligibility re-derived: 4→11 and 5→9.","explanation":"Same conclusion and same ordered direct edges as the earlier F2 derivation, though in a later call. Re-derivation episode.","fragment":2,"kind":"derive","occurrence":0,"paths":[[4,11],[5,9]],"premiseEdges":[[4,7],[7,9],[9,11],[5,7]],"prior":null,"quote":"Fragment 2: need [2,4,11,5,9] → firstFrom=4, firstTo=11, secondFrom=5, secondTo=9. Need directed paths 4→11 and 5→9 in source edges. 4→7→9→11 yes. 5→7→9 yes. Eligible.","ready":true},"failure":"quote not present verbatim","index":13},{"annotation":{"claim":"Fragment 2 eligibility: 4→11 and 5→9.","explanation":"Same conclusion and same ordered direct edges as previous F2 derivations; re-derivation episode.","fragment":2,"kind":"derive","occurrence":0,"paths":[[4,11],[5,9]],"premiseEdges":[[4,7],[7,9],[9,11],[5,7]],"prior":null,"quote":"id10 fragment 2: need firstFrom 4 to 11? Wait fragment 2: [2,4,11,5,9] meaning need path 4->11 and 5->9. Check edges: 4->7->9->11 yes 4 to 11 exists (4->7,7->9,9->11). 5->7->9 yes 5 to 9. So eligible.","ready":true},"failure":"out of chronological order","index":14},{"annotation":{"claim":"Fragment 4 eligibility: 1→7 and 6→11.","explanation":"Same conclusion and same ordered direct edges as earlier F4 derivations; re-derivation episode.","fragment":4,"kind":"derive","occurrence":0,"paths":[[1,7],[6,11]],"premiseEdges":[[1,2],[2,4],[4,7],[6,8],[8,9],[9,11]],"prior":null,"quote":"id11 fragment 4: [4,1,7,6,11] need 1->7 and 6->11. 1->2->4->7 exists. 6->8->9->11 exists (6->8,8->9,9->11). eligible.","ready":true},"failure":"out of chronological order","index":15},{"annotation":{"claim":"Fragment 6 eligibility: 3→8 and 9→11.","explanation":"Same conclusion and same ordered direct edges as earlier F6 derivation.","fragment":6,"kind":"derive","occurrence":0,"paths":[[3,8],[9,11]],"premiseEdges":[[3,6],[6,8],[9,11]],"prior":null,"quote":"id12 fragment 6: [6,3,8,9,11] need 3->8 and 9->11. 3->6->8 yes. 9->11 yes. eligible.","ready":true},"failure":"out of chronological order","index":16},{"annotation":{"claim":"Fragment 0 eligibility: 0→7 and 1→9.","explanation":"Same conclusion and same ordered direct edges as earlier F0 derivation.","fragment":0,"kind":"derive","occurrence":0,"paths":[[0,7],[1,9]],"premiseEdges":[[0,2],[2,4],[4,7],[1,2],[7,9]],"prior":null,"quote":"id13 fragment 0: [0,0,7,1,9] need 0->7 and 1->9. 0->2->4->7 yes. 1->2->4->7->9 yes. eligible.","ready":true},"failure":"out of chronological order","index":17},{"annotation":{"claim":"Fragment 10 ineligible: no path 4→8.","explanation":"Negative eligibility deduction by reachability exhaustion.","fragment":10,"kind":"derive","occurrence":0,"paths":[[4,8]],"premiseEdges":[],"prior":null,"quote":"id14 fragment 10: [10,4,8,5,11] need 4->8 and 5->11. Is 4->8? Edges 4->7->9... 8? 7->9, 9->11, no 8. 4 cannot reach 8. So not eligible.","ready":true},"failure":"out of chronological order","index":18},{"annotation":{"claim":"Fragment 4 eligibility: 1→7 via 1→2→4→7 and 6→11 via 6→8→9→11.","explanation":"Same conclusion and same ordered direct edges as earlier F4 derivations; re-derivation episode.","fragment":4,"kind":"derive","occurrence":0,"paths":[[1,7],[6,11]],"premiseEdges":[[1,2],[2,4],[4,7],[6,8],[8,9],[9,11]],"prior":null,"quote":"Need ensure option 11 eligibility: fragment 4 needs [4,1,7,6,11]. Path 1->7 exists: 1->2 (edge1), 2->4 (edge2), 4->7 (edge4). Path 6->11: 6->8 (edge7), 8->9 (edge9), 9->11 (edge10). Both positive length.","ready":true},"failure":"out of chronological order","index":19},{"annotation":{"claim":"Fragment 4 eligibility with two alternative witnesses for 1→7.","explanation":"Alternative witness derivation for same F4 conclusion.","fragment":4,"kind":"derive","occurrence":0,"paths":[[1,7],[6,11]],"premiseEdges":[[1,2],[2,4],[4,7],[6,8],[8,9],[9,11]],"prior":null,"quote":"Option id11 fragment4: needs [4,1,7,6,11] (frag4). first from 1 to7? path 1->2->4->7 or 1->2->5->7 yes. second 6->11? 6->8->9->11 yes. Eligible.","ready":true},"failure":"out of chronological order","index":20},{"annotation":{"claim":"Fragment 6 eligibility: 3→8 and 9→11.","explanation":"Same conclusion and same ordered direct edges as the earlier F6 derivation, in a later call.","fragment":6,"kind":"derive","occurrence":0,"paths":[[3,8],[9,11]],"premiseEdges":[[3,6],[6,8],[9,11]],"prior":null,"quote":"id12 fragment6 needs [6,3,8,9,11]. first 3->8: 3->6->8 yes. second 9->11 yes. Eligible.","ready":true},"failure":"out of chronological order","index":21},{"annotation":{"claim":"Fragment 0 eligibility: 0→7 and 1→9.","explanation":"Same conclusion and same ordered direct edges as earlier F0 derivations.","fragment":0,"kind":"derive","occurrence":0,"paths":[[0,7],[1,9]],"premiseEdges":[[0,2],[2,4],[4,7],[1,2],[7,9]],"prior":null,"quote":"id13 fragment0 needs [0,0,7,1,9]. first 0->7: 0->2->4->7 yes. second 1->9: 1->2->4->7->9 or via 5 yes. Eligible.","ready":true},"failure":"out of chronological order","index":22},{"annotation":{"claim":"Fragment 10 ineligible: no path 4→8.","explanation":"Negative eligibility deduction; same conclusion as earlier F10 negative check, though not the same positive-derivation identity.","fragment":10,"kind":"derive","occurrence":0,"paths":[[4,8]],"premiseEdges":[],"prior":null,"quote":"id14 fragment10 needs [10,4,8,5,11]. first 4->8? Source edges 4->7->9, no edge to 8. Could 4->7->9->11? no 8. So 4->8 does not exist? Path 4->7->9->8? edge 8->9 only, no 9->8. So not eligible. So discard 14.","ready":true},"failure":"out of chronological order","index":23},{"annotation":{"claim":"Fragment 2 eligibility: 4→11 and 5→9.","explanation":"Same conclusion and same ordered direct edges as earlier F2 derivations; re-derivation episode.","fragment":2,"kind":"derive","occurrence":0,"paths":[[4,11],[5,9]],"premiseEdges":[[4,7],[7,9],[9,11],[5,7]],"prior":null,"quote":"Option id10 fragment 2: needs for fragment 2 is [2,4,11,5,9]? Wait source needs list indexed: ... first path from 4 to 11? second from 5 to 9. Need both directed paths exist. Source edges: 4->7,7->9,9->11 gives 4->11 yes. 5->7->9 gives 5->9 yes. Eligible. Option id10.","ready":true},"failure":"quote not present verbatim","index":24},{"annotation":{"claim":"Fragment 6 eligibility: 3→8 and 9→11.","explanation":"Same conclusion and same ordered direct edges as earlier F6 derivations; additional textual re-derivation.","fragment":6,"kind":"derive","occurrence":1,"paths":[[3,8],[9,11]],"premiseEdges":[[3,6],[6,8],[9,11]],"prior":null,"quote":"id12 fragment6 needs [6,3,8,9,11]. first 3->8: 3->6->8 yes. second 9->11 yes. Eligible.","ready":true},"failure":"quote not present verbatim","index":25},{"annotation":{"claim":"Fragment 0 eligibility: 0→7 and 1→9.","explanation":"Same conclusion and same ordered direct edges as earlier F0 derivations.","fragment":0,"kind":"derive","occurrence":1,"paths":[[0,7],[1,9]],"premiseEdges":[[0,2],[2,4],[4,7],[1,2],[7,9]],"prior":null,"quote":"id13 fragment0 needs [0,0,7,1,9]. first 0->7: 0->2->4->7 yes. second 1->9: 1->2->4->7->9 or via 5 yes. Eligible.","ready":true},"failure":"quote not present verbatim","index":26},{"annotation":{"claim":"Fragment 4 eligibility: 1→7 and 6→11.","explanation":"Same conclusion and same ordered direct edges as earlier F4 derivations.","fragment":4,"kind":"derive","occurrence":1,"paths":[[1,7],[6,11]],"premiseEdges":[[1,2],[2,4],[4,7],[6,8],[8,9],[9,11]],"prior":null,"quote":"Need ensure option 11 eligibility: fragment 4 needs [4,1,7,6,11]. Path 1->7 exists: 1->2 (edge1), 2->4 (edge2), 4->7 (edge4). Path 6->11: 6->8 (edge7), 8->9 (edge9), 9->11 (edge10). Both positive length.","ready":true},"failure":"quote not present verbatim","index":27},{"annotation":{"claim":"Fragment 0 eligible citing already-known path results F47 and F57.","explanation":"Explicitly cites established results without deriving the edge chains.","fragment":0,"kind":"reuse","occurrence":0,"paths":[[0,7],[1,9]],"premiseEdges":[],"prior":null,"quote":"Let me check needs: fragment 0: [0,0,7,1,9] → path 0→7 exists (F47 path 0,7 exists), path 1→9 exists (F57). Eligible.","ready":true},"failure":"quote not present verbatim","index":28},{"annotation":{"claim":"Fragment 5 eligibility: 2→7 and 8→11.","explanation":"Same conclusion as earlier F5 derivation and same ordered direct edges chosen.","fragment":5,"kind":"derive","occurrence":0,"paths":[[2,7],[8,11]],"premiseEdges":[[2,4],[4,7],[8,9],[9,11]],"prior":null,"quote":"Option 16: fragment5 needs 2→7 and 8→11. Edges: 2-4-7 or 2-5-7 yes. 8-9-11 yes. Eligible.","ready":true},"failure":"quote not present verbatim","index":39},{"annotation":{"claim":"Ambiguous fragment check apparently mis-stated: mentions 3→8/9→11 for what is labeled fragment 4.","explanation":"Fragment label conflicts with the path endpoints stated; kept as uncertain/ambiguous.","fragment":4,"kind":"uncertain","occurrence":0,"paths":[[3,8],[9,11]],"premiseEdges":[],"prior":null,"quote":"Fragment 4: need [4,1,7,6,11] → paths 1→7 and 6→11. Edges: 3→6, 6→8 gives 3→8. 9→11 exists.","ready":null},"failure":"quote not present verbatim","index":40},{"annotation":{"claim":"Fragment 4 stated eligible for choosing option 33.","explanation":"Asserted eligibility without re-deriving chains.","fragment":4,"kind":"mention","occurrence":0,"paths":[[1,7],[6,11]],"premiseEdges":[],"prior":null,"quote":"Option 33 cost36 risk38 value326 fragment4. Or option31 cost42 risk41 value376 highest value but cost/risk high. Option33 best tradeoff lower cost/risk. Need eligible fragment4 yes.","ready":true},"failure":"quote not present verbatim","index":41},{"annotation":{"claim":"Ambiguity about whether fragment 10 is among ready fragments.","explanation":"Ambiguous eligibility-related reasoning; no concrete path endpoints derived. It does reference provenance vs ready set, but no explicit path fact to anchor, so omit paths or keep empty. I'll keep it but with empty paths to avoid inventing. Actually guidelines require one endpoint pair for path-only episodes; this is not a path episode, so kind uncertain with empty paths is acceptable? The schema expects paths array; empty is fine for non-path ambiguity. But to be safe, this is meta-ambiguity not a path fact, so I'll drop it to avoid noise.","fragment":null,"kind":"uncertain","occurrence":0,"paths":[],"premiseEdges":[],"prior":null,"quote":"Actually wait, fragment field in option might be the fragment id, but the readyFragments list is [0..7], so fragments 8,9,10,11 might not be \"ready\". But the options include fragment 10 (id 34). Hmm.","ready":null},"failure":"out of chronological order","index":42},{"annotation":{"claim":"Fragment 10 requires 4→8 and 5→11.","explanation":"Restating the need specification without inference.","fragment":10,"kind":"mention","occurrence":0,"paths":[[4,8],[5,11]],"premiseEdges":[],"prior":null,"quote":"Actually, let me reconsider: fragment 10 needs [10,4,8,5,11]. Actually maybe needs columns are [fragmentId, firstFrom, firstTo, secondFrom, secondTo]. So fragment 10: first path 4->8, second path 5->11.","ready":null},"failure":"quote not present verbatim","index":44}]

## paid/branch-search-4-retained-1

Text SHA `5aa2ea21ccf725f64cf45e227e9b3a383bc299eb66df9e21c8f08352e89e2858`; annotation failure `annotation_validation:Invalid \escape: line 1 column 6373 (char 6372)`.

