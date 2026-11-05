package com.firesideafrica.fireside_group;

import android.content.Context;
import androidx.work.*;
import androidx.work.impl.WorkManagerImpl;
import androidx.work.testing.*;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.*;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;
import static org.junit.Assert.*;

/** Real AndroidX/Room host fixture, NOT a Flutter-engine or physical-phone test. */
@RunWith(RobolectricTestRunner.class)
@Config(manifest = Config.NONE, sdk = 33)
public class UpdateWorkManagerHostTest {
    private WorkManager manager;
    private TestDriver driver;
    private static final String NAME = "fireside.update.authenticated-check.v2";
    private static final AtomicInteger calls = new AtomicInteger();

    public static class CheckWorker extends Worker {
        public CheckWorker(Context context, WorkerParameters params) { super(context, params); }
        @Override public Result doWork() { calls.incrementAndGet(); return Result.success(); }
    }
    public static class RetryWorker extends Worker {
        public RetryWorker(Context context, WorkerParameters params) { super(context, params); }
        @Override public Result doWork() { calls.incrementAndGet(); return Result.retry(); }
    }
    @Before public void setup() {
        calls.set(0);
        Context context = RuntimeEnvironment.getApplication();
        WorkManagerTestInitHelper.initializeTestWorkManager(context,
            new Configuration.Builder().setExecutor(new SynchronousExecutor()).build());
        manager = WorkManager.getInstance(context);
        driver = WorkManagerTestInitHelper.getTestDriver(context);
    }
    @After public void teardown() throws Exception {
        manager.cancelAllWork().getResult().get();
        WorkManagerTestInitHelper.closeWorkDatabase();
    }
    private PeriodicWorkRequest request(Class<? extends ListenableWorker> worker) {
        return new PeriodicWorkRequest.Builder(worker, 15, TimeUnit.MINUTES)
            .setInitialDelay(3, TimeUnit.HOURS)
            .setConstraints(new Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 15, TimeUnit.MINUTES).build();
    }
    @Test public void keepPreservesUniqueEnrollmentAndCredentialFreeDatabaseSpec() throws Exception {
        PeriodicWorkRequest first = request(CheckWorker.class);
        manager.enqueueUniquePeriodicWork(NAME, ExistingPeriodicWorkPolicy.KEEP, first).getResult().get();
        manager.enqueueUniquePeriodicWork(NAME, ExistingPeriodicWorkPolicy.KEEP, request(CheckWorker.class)).getResult().get();
        assertEquals(1, manager.getWorkInfosForUniqueWork(NAME).get().size());
        assertEquals(first.getId(), manager.getWorkInfosForUniqueWork(NAME).get().get(0).getId());
        androidx.work.impl.model.WorkSpec spec = ((WorkManagerImpl)manager).getWorkDatabase()
            .workSpecDao().getWorkSpec(first.getId().toString());
        assertNotNull(spec);
        assertEquals(3 * 60 * 60 * 1000L, spec.initialDelay);
        assertEquals(15 * 60 * 1000L, spec.intervalDuration);
        assertEquals(BackoffPolicy.EXPONENTIAL, spec.backoffPolicy);
        assertEquals(NetworkType.CONNECTED, spec.constraints.getRequiredNetworkType());
        assertTrue(spec.input.getKeyValueMap().isEmpty());
        assertEquals(0, calls.get());
    }
    @Test public void connectedConstraintAndInitialDelayBothGateExecution() throws Exception {
        PeriodicWorkRequest work = request(CheckWorker.class);
        manager.enqueueUniquePeriodicWork(NAME, ExistingPeriodicWorkPolicy.KEEP, work).getResult().get();
        assertEquals(0, calls.get());
        driver.setInitialDelayMet(work.getId());
        assertEquals(0, calls.get());
        driver.setAllConstraintsMet(work.getId());
        assertEquals(1, calls.get());
        assertEquals(WorkInfo.State.ENQUEUED, manager.getWorkInfoById(work.getId()).get().getState());
    }
    @Test public void failureRecordsRetryWithoutCompletingPeriodicEnrollment() throws Exception {
        PeriodicWorkRequest work = request(RetryWorker.class);
        manager.enqueueUniquePeriodicWork(NAME, ExistingPeriodicWorkPolicy.KEEP, work).getResult().get();
        driver.setInitialDelayMet(work.getId());
        driver.setAllConstraintsMet(work.getId());
        WorkInfo info = manager.getWorkInfoById(work.getId()).get();
        assertEquals(1, calls.get());
        assertEquals(1, info.getRunAttemptCount());
        assertEquals(WorkInfo.State.ENQUEUED, info.getState());
    }
}
