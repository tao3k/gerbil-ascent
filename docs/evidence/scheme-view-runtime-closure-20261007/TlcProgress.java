// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Read-only TLC counters; never emits a heartbeat for unchanged state work.
public final class TlcProgress {
  public static void main(String[] args) throws Exception {
    Thread reporter = new Thread(() -> {
      long previous = 0;
      try {
        while (true) {
          Thread.sleep(1000);
          if (tlc2.TLCGlobals.mainChecker instanceof tlc2.tool.ModelChecker checker) {
            long generated = checker.getStatesGenerated();
            if (generated > previous) {
              System.err.printf("TLC-ACTUAL-STATES generated=%d distinct=%d queued=%d%n",
                  generated, checker.getDistinctStatesGenerated(), checker.getStateQueueSize());
              previous = generated;
            }
          }
        }
      } catch (InterruptedException stop) {
        Thread.currentThread().interrupt();
      }
    }, "TLC completed-state counters");
    reporter.setDaemon(true);
    reporter.start();
    tlc2.TLC.main(args);
  }
}
