--
-- Show information about Oracle sessions
--

SELECT s.inst_id, s.osuser, gps.qcsid, p.spid, s.sid, s.serial#
     , s.machine, s.schemaname, s.program, w.event AS wait_event
FROM   gv$session s
JOIN   gv$process p ON p.addr = s.paddr
LEFT OUTER JOIN gv$session_wait w ON w.sid = s.sid
LEFT OUTER JOIN gv$px_session gps ON gps.sid = s.sid AND gps.serial# = s.serial#
WHERE s.osuser != 'SYSTEM'
-- Show sessions on a particular instance of the RAC
-- AND s.inst_id = 1
-- Show sessions for the particular OS user
-- AND s.osuser LIKE 'sergey%'
-- If you know the session ID
-- AND s.sid = 11
-- If you know the OS process ID
-- AND pid = 22
-- If you know the name of the application accessing the database
-- AND Lower(s.program) LIKE 'sqlplus%'
/