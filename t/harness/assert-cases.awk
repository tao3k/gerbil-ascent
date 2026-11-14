# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
/^MODULE / { current_module = substr($0, 8); cases = 0 }
/^CASE / { cases++ }
/^MODULE-OK / && cases == 0 {
    print "[ascent-test] FAIL no discovered Cases in " current_module > "/dev/stderr"
    empty_module = 1
}
END { exit empty_module ? 1 : 0 }
