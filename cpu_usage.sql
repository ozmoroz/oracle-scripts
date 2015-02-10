-- This script prints the top sessions by their CPU usage within a given time interval
-- (as defined by k_interval_sec constantm default 30 sec).
-- It prints the result into dbms_output in the following CSV format:
--   sid, serial#, cpu_seconds

DECLARE

   -- Interval before the snapshots
   k_interval_sec CONSTANT PLS_INTEGER := 30;

   -- Cursor gets the CPU seconds per session.
   -- This number may be higher than total SCNDS_SINCE_LOG IF you have more than one CPU.
   CURSOR c_cpu_sec
   IS
      SELECT TO_CHAR(a.sid) || ':' || TO_CHAR(c.serial#) AS hash_value,
            a.sid,
            c.serial#,
            TRUNC(a.VALUE / 100) AS cpu_seconds
      FROM   v$sesstat a
      JOIN   v$sysstat b ON a.statistic# = b.statistic#
      JOIN   v$session c ON c.sid = a.sid
      LEFT OUTER JOIN  v$process d ON c.paddr = d.addr
      WHERE b.name = 'CPU used by this session'
      ORDER BY a.sid DESC;

   TYPE cpu_usage_rec_t IS RECORD (
      hash_value      VARCHAR2(50),
      sid             NUMBER,
      serial#         NUMBER,
      cpu_sec_before  NUMBER,
      cpu_sec_after   NUMBER,
      cpu_sec_elapsed NUMBER
   );

   TYPE cpu_sec_tab_t   IS TABLE OF c_cpu_sec%ROWTYPE INDEX BY PLS_INTEGER;

   -- Collection of CPU measurements with SID:SERIAL# as a key.
   TYPE cpu_usage_tab_t IS TABLE OF cpu_usage_rec_t INDEX BY VARCHAR2(50);

   -- Collection of SID:SERIAL# hash keys
   TYPE usage_idx_tab_t IS TABLE OF VARCHAR2(50) INDEX BY PLS_INTEGER;

   usage_rec      cpu_usage_rec_t;

   cpu_sec_tab    cpu_sec_tab_t;
   cpu_usage_tab  cpu_usage_tab_t;
   usage_idx_tab  usage_idx_tab_t;

   i    INTEGER;
   hval VARCHAR2(50);
   l_string VARCHAR2(5000);

   --
   -- Function sorts PL/SQL collection
   --

   FUNCTION sort_collection (i_usage_tab IN cpu_usage_tab_t)
   RETURN usage_idx_tab_t
   IS
      idx_tab   usage_idx_tab_t;

      i           PLS_INTEGER;
      l_hash_key  VARCHAR2(50);
      l_swaps_cnt PLS_INTEGER;

   BEGIN
      -- Fill the index collection with hash keys of i_usage_tab collection

      i := 1;
      l_hash_key := i_usage_tab.FIRST;
      LOOP
         idx_tab(i) := l_hash_key;
         i := i + 1;
         l_hash_key := i_usage_tab.NEXT(l_hash_key);
         EXIT WHEN l_hash_key IS NULL;
      END LOOP;

      FOR i IN 1 .. idx_tab.COUNT LOOP
         l_swaps_cnt := 0;

         FOR j IN i+1 .. idx_tab.COUNT LOOP
            IF i_usage_tab(idx_tab(j)).cpu_sec_elapsed > i_usage_tab(idx_tab(i)).cpu_sec_elapsed THEN
               -- Swap 2 items of the index table
               l_hash_key := idx_tab(j);
               idx_tab(j) := idx_tab(i);
               idx_tab(i) := l_hash_key;
               l_swaps_cnt := l_swaps_cnt + 1;
            END IF;
         END LOOP;
      END LOOP;

   -- Return the index table
      RETURN idx_tab;
   END sort_collection;

BEGIN
   DBMS_OUTPUT.ENABLE(NULL);

   -- Take a snapshot of CPU seconds by sessions
   OPEN c_cpu_sec;
   FETCH c_cpu_sec BULK COLLECT INTO cpu_sec_tab;
   CLOSE c_cpu_sec;

   FOR i IN 1 .. cpu_sec_tab.COUNT() LOOP
      hval := cpu_sec_tab(i).hash_value;
      cpu_usage_tab(hval).sid     := cpu_sec_tab(i).sid;
      cpu_usage_tab(hval).serial# := cpu_sec_tab(i).serial#;
      cpu_usage_tab(hval).cpu_sec_before := cpu_sec_tab(i).cpu_seconds;
   END LOOP;

   -- Sleep for a number of seconds
   DBMS_LOCK.sleep(k_interval_sec);

   -- Repeat the data collection
   OPEN  c_cpu_sec;
   FETCH c_cpu_sec BULK COLLECT INTO cpu_sec_tab;
   CLOSE c_cpu_sec;

   FOR i IN 1 .. cpu_sec_tab.COUNT() LOOP
      hval := cpu_sec_tab(i).hash_value;
      cpu_usage_tab(hval).sid     := cpu_sec_tab(i).sid;
      cpu_usage_tab(hval).serial# := cpu_sec_tab(i).serial#;
      cpu_usage_tab(hval).cpu_sec_after := cpu_sec_tab(i).cpu_seconds;
      cpu_usage_tab(hval).cpu_sec_elapsed := ROUND(NVL(cpu_usage_tab(hval).cpu_sec_after, 0)
                                          - NVL(cpu_usage_tab(hval).cpu_sec_before, 0), 0);
   END LOOP;

   -- Sort the results by top cpu_sec_elapsed
   usage_idx_tab := sort_collection(cpu_usage_tab);

   -- Print the top sessions
   DBMS_OUTPUT.Put_Line('Top sessions by CPU usage within ' || k_interval_sec || ' seconds:');
   DBMS_OUTPUT.Put_Line('SID,Serial#,cpu_elapsed_sec');

   FOR i IN 1 .. usage_idx_tab.COUNT LOOP
      usage_rec := cpu_usage_tab(usage_idx_tab(i));
      IF usage_rec.cpu_sec_elapsed != 0 THEN
         l_string := TO_CHAR(usage_rec.sid) || ',' || TO_CHAR(usage_rec.serial#)
                     || ',' || TO_CHAR(ROUND(usage_rec.cpu_sec_elapsed, 0));
         DBMS_OUTPUT.Put_Line(l_string);
      END IF;
   END LOOP;
END;
/