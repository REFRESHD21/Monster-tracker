package au.monster.tracker;

import org.junit.Test;

/** Executes the same 26 production-ledger/backup checks through Gradle's Android unit-test task. */
public final class OfflineCoreUnitTest {
    @Test public void existingLedgerAndBackupChecks() throws Exception {
        CoreTests.main(new String[0]);
    }
}
