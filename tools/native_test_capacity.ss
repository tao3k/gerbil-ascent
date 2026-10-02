;;; Use the pinned ASP Build API's capacity projection; do not duplicate it.
(import (only-in :asp-gerbil-scheme/src/build-api/core-capacity
                 initialize-native-build-core-capacity!))
(displayln (inexact->exact (initialize-native-build-core-capacity!)))
