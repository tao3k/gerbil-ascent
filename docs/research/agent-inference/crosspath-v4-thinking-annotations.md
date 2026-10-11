# Frozen direct-derivation annotations, branch search

Source text is returned external-model reasoning. Exact half-open Unicode character spans are validated. Definite repeats require an earlier grounded derivation with identical conclusion and ordered explicit premises; alternative witnesses and goal-dependent checks remain separate. Extraction is not independent human ground truth.

## paid/branch-search-6-baseline-0

Text SHA `bc99afdab7bc083a16964eb6160eb737b24df0a1a3c169d009b816e28cd806ae`; annotation failure `annotation_provider_incomplete_or_error`.

## paid/branch-search-6-baseline-1

Text SHA `2da921cbfaa186b9c7b856c7a8daaf847e0c1d12326d4879a0d82f0bafeb3b43`; annotation failure `annotation_provider_incomplete_or_error`.

## paid/branch-search-6-fresh-0

Text SHA `1c479df99fa610ddb73829998e0a221ad3deb2e2b70a02df84804859cff758f5`; annotation failure `annotation_provider_incomplete_or_error`.

## paid/branch-search-6-fresh-1

Text SHA `68f9a9cca0e079dda7294b3cd4dd2b80bb4c9595c08cfe47418e0b3f036e8201`; annotation failure `None`.

- Episode 0: derive; F0; span [460, 684]; prior None; definite repeat False; native truth True

> Fragment 0 need [0,0,7,1,9]: first path 0->7, second 1->9. Do both exist in transitive closure? Edges: 0->2->4->7 yes (0-2,2-4,4-7). 1->2->4->7? 1->2->4->7->9? Edges 7->9 yes, so 1->9 yes. Both positive length yes. Eligible.

- Episode 1: derive; F2; span [686, 778]; prior None; definite repeat False; native truth True

> Fragment2 need [2,4,11,5,9]: path 4->11? edges 4->7->9->11 yes; 5->9? 5->7->9 yes. Eligible.

- Episode 2: derive; F4; span [780, 863]; prior None; definite repeat False; native truth True

> Fragment4 need [4,1,7,6,11]: path 1->7 yes; 6->11? edges 6->8->9->11 yes. Eligible.

- Episode 3: derive; F6; span [865, 944]; prior None; definite repeat False; native truth True

> Fragment6 need [6,3,8,9,11]: path 3->8? edges 3->6->8 yes; 9->11 yes. Eligible.

- Episode 4: derive; F8; span [946, 1141]; prior None; definite repeat False; native truth True

> Fragment8 need [8,0,8,1,7]: path 0->8? edges 0->2->4->7->9? to 8? no 9->11, 8->9. path 0 to 8? 0->2->4->7->9 cannot go 8; 2->5->7->9 no. No reverse. So 0->8 likely missing. Fragment 8 ineligible.

- Episode 5: derive; F9; span [3910, 4089]; prior None; definite repeat False; native truth True

> id9 fragment9: paths 3->7 and 2->9. 3->7? 3->6->8->9? 9 can't to 7 (directed 7->9 not 9->7). Any other from 3: 3->6->8->9, no 7. So 3->7 does NOT exist. Thus fragment9 ineligible.

- Episode 10: reuse; F2; span [10419, 10481]; prior None; definite repeat False; native truth True

> fragment 2 need: 4→11 and 5→9. Both exist. So eligible likely.

- Episode 12: derive; F6; span [13238, 13363]; prior 3; definite repeat True; native truth True

> fragment 6: [6,3,8,9,11]? Actually fragment 6 = [6,3,8,9,11] means first 3→8 exists 3→6→8; second 9→11 exists 9→11. Both yes.

- Episode 13: derive; F0; span [13364, 13458]; prior 0; definite repeat True; native truth True

> fragment 0: [0,0,7,1,9] means 0→7 exists 0→2→4→7 or via 5; 1→9 exists 1→2→4→7→9 etc. Both yes.

- Episode 14: derive; F10; span [13459, 13679]; prior None; definite repeat False; native truth True

> fragment 10: [10,4,8,5,11] means 4→8? Source edges 4→7, 7→9, 9→11, no 8. Is there 4→? 4→7→9→11; no 8. 5→11 exists 5→7→9→11. But 4→8 does not exist because 7 cannot go to 8 (edge 6→8, 8→9 only). So fragment 10 ineligible.

- Episode 19: derive; F11; span [17350, 17466]; prior None; definite repeat False; native truth True

> Fragment 11: first 10->9: Is there path 10 to 9? Edge 10->11, then 11? no outgoing from 11. No 10->9. So ineligible.

- Episode 21: derive; F6; span [21228, 21319]; prior 3; definite repeat True; native truth True

> Fragment 6: needs[6]=[6,3,8,9,11]. path 3->8? 3->6->8 yes. path 9->11? 9->11 yes. Eligible.

- Episode 22: derive; F0; span [21321, 21421]; prior 0; definite repeat True; native truth True

> Fragment 0: needs[0]=[0,0,7,1,9]. path 0->7? 0->2->4->7 yes. path 1->9? 1->2->4->7->9 yes. Eligible.

- Episode 23: derive; F2; span [21423, 21520]; prior 1; definite repeat True; native truth True

> Fragment 2: needs[2]=[2,4,11,5,9]. path 4->11? 4->7->9->11 yes. path 5->9? 5->7->9 yes. Eligible.

- Episode 24: derive; F8; span [21522, 21843]; prior 4; definite repeat False; native truth True

> Fragment 8: needs[8]=[8,0,8,1,7]. path 0->8? 0->2->4->7->9... no to 8. 0->2->5->7->9, 8->9 edge means 8->9, but we need 0->8. Path from 0 to 8? Edges: 0->2, 2->4/5, 4->7, 5->7, 7->9, 8->9. No edge into 8 except from 6 (6->8) and from... 3->6->8. So 0->...->8? 0->2->...->7->9 no 8. So no path 0->8. Fragment 8 ineligible.

- Episode 26: derive; F9; span [25173, 25408]; prior 5; definite repeat False; native truth True

> id29 fragment9 need [9,3,7,2,9]: first 3->7? Let's check directed edges: 3->6->8->9->11, no to 7. Need firstFrom=3 firstTo=7. Is there path 3 to 7? Source edges: [3,6],[6,8],[8,9],[9,11],[10,11]; no edge to 7. So fragment 9 ineligible?

- Episode 27: derive; F6; span [32309, 32543]; prior 3; definite repeat True; native truth True

> Option 30: fragment 6. Need for fragment 6: row 18: [6,3,8,9,11]. So paths [3,8] and [9,11]. Check source edges: path [3,8]? edges: 3->6, 6->8. Yes path exists (rule 43). Path [9,11]: edge 9->11 exists (rule 34). Both exist. Eligible.

- Episode 29: derive; F2; span [32711, 32857]; prior 1; definite repeat True; native truth True

> Option 32: fragment 2. Need row 14: [2,4,11,5,9]. Paths [4,11] and [5,9]. [4,11]: 4->7->9->11 yes (rule50). [5,9]: 5->7->9 yes (rule42). Eligible.

- Episode 31: derive; F2; span [53103, 53201]; prior 1; definite repeat True; native truth True

> Option 32 fragment 2. Path 4->11 exists? 4->7->9->11 yes. Path 5->9 exists? 5->7->9 yes. Eligible.

- Episode 33: mention; F10; span [54901, 55222]; prior None; definite repeat False; native truth False

> Wait, the option is fragment 10. Need to check eligibility: both positive-length directed paths of fragment F exist in source edges. Fragment 10 corresponds to need at derivation node 22: [10,4,8,5,11] meaning fragmentId 10, firstFrom 4, firstTo 8, secondFrom 5, secondTo 11. So need paths 4->8 and 5->11 in source edges.

Rejected labels retained:
[{"annotation":{"claim":"Fragment 1 eligible: both required paths 2→9 and 3→11 exist.","explanation":"Derives both required paths for fragment 1.","fragment":1,"kind":"derive","occurrence":0,"paths":[[2,9],[3,11]],"premiseEdges":[[2,4],[4,7],[7,9],[3,6],[6,8],[8,9],[9,11]],"prior":null,"quote":"option id5 fragment 1: paths 2->9 and 3->11. 2->9? 2->4->7->9 yes (2->4,4->7,7->9). 3->11? 3->6->8->9->11 yes. Eligible.","ready":true},"failure":"out of chronological order","index":6},{"annotation":{"claim":"Fragment 3 eligible: both required paths 0→11 and 3→9 exist.","explanation":"Derives both required paths for fragment 3.","fragment":3,"kind":"derive","occurrence":0,"paths":[[0,11],[3,9]],"premiseEdges":[[0,2],[2,5],[5,7],[7,9],[9,11],[3,6],[6,8],[8,9]],"prior":null,"quote":"id6 fragment3: paths 0->11 and 3->9. 0->11? 0->2->5->7->9->11? yes 0->2,2->5,5->7,7->9,9->11. 3->9? 3->6->8->9 yes. Eligible.","ready":true},"failure":"out of chronological order","index":7},{"annotation":{"claim":"Fragment 5 eligible: both required paths 2→7 and 8→11 exist.","explanation":"Derives both required paths for fragment 5.","fragment":5,"kind":"derive","occurrence":0,"paths":[[2,7],[8,11]],"premiseEdges":[[2,4],[4,7],[8,9],[9,11]],"prior":null,"quote":"id7 fragment5: paths 2->7 and 8->11. 2->7? 2->4->7 or 2->5->7 yes. 8->11? 8->9->11 yes. Eligible.","ready":true},"failure":"out of chronological order","index":8},{"annotation":{"claim":"Fragment 7 eligible: both required paths 0→9 and 10→11 exist.","explanation":"Derives both required paths for fragment 7.","fragment":7,"kind":"derive","occurrence":0,"paths":[[0,9],[10,11]],"premiseEdges":[[0,2],[2,4],[4,7],[7,9],[10,11]],"prior":null,"quote":"id8 fragment7: paths 0->9 and 10->11. 0->9? 0->2->4->7->9 yes. 10->11 yes. Eligible.","ready":true},"failure":"out of chronological order","index":9},{"annotation":{"claim":"Fragment 4 eligible: both required paths 1→7 and 6→11 exist.","explanation":"Rederives same fragment 4 conclusion from same source edges; duplicate derivation episode.","fragment":4,"kind":"derive","occurrence":0,"paths":[[1,7],[6,11]],"premiseEdges":[[1,2],[2,4],[4,7],[6,8],[8,9],[9,11]],"prior":2,"quote":"fragment 4 need [1,7,6,11]. Path 1→7: 1→2→4→7 or 1→2→5→7 yes. Path 6→11: 6→8→9→11 yes. So eligible.","ready":true},"failure":"different conclusion/premise context","index":11},{"annotation":{"claim":"Fragment 3 eligible: both required paths 0→11 and 3→9 exist.","explanation":"Duplicate rederivation of fragment 3 eligibility from same edges.","fragment":3,"kind":"derive","occurrence":0,"paths":[[0,11],[3,9]],"premiseEdges":[[0,2],[2,4],[4,7],[7,9],[9,11],[3,6],[6,8],[8,9]],"prior":6,"quote":"Fragment 3: first 0->11 exists? Yes 0->2->4->7->9->11 or 0->2->5->7->9->11. second 3->9? 3->6->8->9 yes. Both exist. So eligible.","ready":true},"failure":"quote not present verbatim","index":15},{"annotation":{"claim":"Fragment 5 eligible: both required paths 2→7 and 8→11 exist.","explanation":"Duplicate rederivation of fragment 5 eligibility from same edges.","fragment":5,"kind":"derive","occurrence":0,"paths":[[2,7],[8,11]],"premiseEdges":[[2,4],[4,7],[8,9],[9,11]],"prior":7,"quote":"Fragment 5: first 2->7: 2->4->7 or 2->5->7 yes. second 8->11: 8->9->11 yes. Eligible.","ready":true},"failure":"prior annotation was rejected","index":16},{"annotation":{"claim":"Fragment 7 eligible: both required paths 0→9 and 10→11 exist.","explanation":"Duplicate rederivation of fragment 7 eligibility from same edges.","fragment":7,"kind":"derive","occurrence":0,"paths":[[0,9],[10,11]],"premiseEdges":[[0,2],[2,4],[4,7],[7,9],[10,11]],"prior":9,"quote":"Fragment 7: first 0->9: 0->2->4->7->9 yes. second 10->11: edge 10->11 yes. Eligible.","ready":true},"failure":"prior annotation was rejected","index":17},{"annotation":{"claim":"Fragment 1 eligible: both required paths 2→9 and 3→11 exist.","explanation":"Duplicate rederivation of fragment 1 eligibility from same edges.","fragment":1,"kind":"derive","occurrence":0,"paths":[[2,9],[3,11]],"premiseEdges":[[2,4],[4,7],[7,9],[3,6],[6,8],[8,9],[9,11]],"prior":5,"quote":"Fragment 1: first 2->9: 2->4->7->9 or 2->5->7->9 yes. second 3->11: 3->6->8->9->11 yes. Eligible.","ready":true},"failure":"different conclusion/premise context","index":18},{"annotation":{"claim":"Fragment 4 eligible: both required paths 1→7 and 6→11 exist.","explanation":"Duplicate rederivation of fragment 4 eligibility from same edges.","fragment":4,"kind":"derive","occurrence":0,"paths":[[1,7],[6,11]],"premiseEdges":[[1,2],[2,4],[4,7],[6,8],[8,9],[9,11]],"prior":2,"quote":"Check fragment 4: path 1->7? From 1: 1->2->4->7 yes. path 6->11? From 6: 6->8->9->11 yes. So fragment 4 eligible.","ready":true},"failure":"different conclusion/premise context","index":20},{"annotation":{"claim":"Fragment 3 eligible: both required paths 0→11 and 3→9 exist.","explanation":"Duplicate rederivation of fragment 3; explicit chain for 3→9 only.","fragment":3,"kind":"derive","occurrence":0,"paths":[[0,11],[3,9]],"premiseEdges":[[3,6],[6,8],[8,9]],"prior":6,"quote":"id28 fragment3 need [3,0,11,3,9]: first 0->11 exists; second 3->9 exists 3->6->8->9. Eligible. cost7 risk6 values [35,44], prefixTotals cost45 risk31 val263, suffix cost48 risk36 val349.","ready":true},"failure":"prior annotation was rejected","index":25},{"annotation":{"claim":"Fragment 0 eligible: both required paths 0→7 and 1→9 exist.","explanation":"Duplicate rederivation of fragment 0.","fragment":0,"kind":"derive","occurrence":0,"paths":[[0,7],[1,9]],"premiseEdges":[[0,2],[2,4],[4,7],[1,2]],"prior":0,"quote":"Option 31: fragment 0. Need row 12: [0,0,7,1,9]. Paths [0,7] and [1,9]. [0,7]: 0->2->4->7 or 0->2->5->7. Yes (rule 47). [1,9]: 1->2->...->9 yes (rule 57). Eligible.","ready":true},"failure":"different conclusion/premise context","index":28},{"annotation":{"claim":"Fragment 10 ineligible: required path 4→8 unreachable.","explanation":"Duplicate negative derivation of fragment 10 ineligibility.","fragment":10,"kind":"derive","occurrence":0,"paths":[[4,8],[5,11]],"premiseEdges":[],"prior":15,"quote":"Option 34: fragment 10. Need row 22: [10,4,8,5,11]. Paths [4,8] and [5,11]. [4,8]: edges 4->7, 7->9, 9->11... need to reach 8? 6->8, 3->6. From 4 can we get to 8? Paths: 4->7->9->11 no edges to 8 except 6->8. No edge into 6 except 3->6. So [4,8] not reachable. Not eligible.","ready":false},"failure":"prior annotation was rejected","index":30},{"annotation":{"claim":"Fragment 10 ineligible: required path 4→8 missing.","explanation":"Duplicate negative derivation of fragment 10 ineligibility.","fragment":10,"kind":"derive","occurrence":0,"paths":[[4,8],[5,11]],"premiseEdges":[],"prior":15,"quote":"Option 34 fragment 10. Need [10,4,8,5,11] => first 4->8, second 5->11. 4->8? 4->7->9->? no 9->11, no 8. 4->7->9->? not 8. 5->11? 5->7->9->11 yes. First 4->8 not exists likely. So option 34 ineligible.","ready":false},"failure":"prior annotation was rejected","index":32},{"annotation":{"claim":"Fragment 10 ineligible: path 4→8 does not exist.","explanation":"Duplicate negative derivation of fragment 10 ineligibility.","fragment":10,"kind":"derive","occurrence":0,"paths":[[4,8],[5,11]],"premiseEdges":[],"prior":15,"quote":"Path 4->8: 4->7->9? 9->? 9->11, no 8. 4->7, 7->9, 9->11. No 8. Hmm, also 6->8 exists but 4->... can we reach 6? No edges into 6 except 3->6. So 4->8 does not exist.","ready":false},"failure":"prior annotation was rejected","index":34},{"annotation":{"claim":"Fragment 10 ineligible: 5→11 exists but 4→8 does not.","explanation":"Duplicate negative derivation of fragment 10.","fragment":10,"kind":"derive","occurrence":0,"paths":[[4,8],[5,11]],"premiseEdges":[[5,7],[7,9],[9,11]],"prior":15,"quote":"Check path 5->11: 5->7->9->11 yes (rule 51 path [5,11] node 51). Path 4->8: does not exist (no derivation node for 4->8). So inadmissible.","ready":false},"failure":"prior annotation was rejected","index":35}]

## paid/branch-search-6-retained-0

Text SHA `8cfac0a324a9f2816f4b048a4e52219b9a79552a6ce2cb6f84a8e5a0c494c678`; annotation failure `annotation_validation:expected exactly one annotation result`.

## paid/branch-search-6-retained-1

Text SHA `f25bb2827a05e4b0387ea43a9b25b06d27286bed3e3f94d95f96c02467eb5295`; annotation failure `annotation_provider_incomplete_or_error`.

