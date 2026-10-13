package au.monster.tracker;

import org.junit.Test;

/** Executes the same 26 production-ledger/backup checks through Gradle's Android unit-test task. */
public final class OfflineCoreUnitTest {
    @Test public void financialReportingChecks() {FinanceTests.main(new String[0]);}
    @Test public void catalogueAndOcrChecks() {CatalogTests.main(new String[0]);}
    @Test public void purchaseAndReceiptChecks() throws Exception {PurchaseTests.main(new String[0]);}
    @Test public void existingLedgerAndBackupChecks() throws Exception {
        CoreTests.main(new String[0]);
    }
}
