-- ============================================================
-- iCloudEMS Support Engineer (AI) - Technical Assignment
-- Executed on MariaDB 10.11 (MySQL-compatible syntax)
-- Outstanding = DUE - PAID - CONCESSION (parent level, per admission_no)
-- ============================================================

-- ################ TASK 1 ################
-- 1.1 Row counts
SELECT 'departments' tbl, COUNT(*) row_count FROM departments
UNION ALL SELECT 'programs', COUNT(*) FROM programs
UNION ALL SELECT 'students', COUNT(*) FROM students
UNION ALL SELECT 'admissions', COUNT(*) FROM admissions
UNION ALL SELECT 'fee_transactions', COUNT(*) FROM fee_transactions
UNION ALL SELECT 'fee_transaction_details', COUNT(*) FROM fee_transaction_details;

-- 1.2 Duplicate admission numbers in students
SELECT s.* FROM students s
JOIN (SELECT admission_no FROM students GROUP BY admission_no HAVING COUNT(*)>1) d USING (admission_no)
ORDER BY s.admission_no, s.student_id;

-- 1.3 Duplicate fee transactions (same admission_no, type, amount, DATE)
-- Date is included because the same student can legitimately pay the same amount
-- in the same type on different days (e.g. monthly instalments); only same-day repeats are true duplicates.
SELECT admission_no, transaction_type, total_amount, transaction_date,
       COUNT(*) occurrences, GROUP_CONCAT(transaction_id ORDER BY transaction_id) transaction_ids
FROM fee_transactions
GROUP BY admission_no, transaction_type, total_amount, transaction_date
HAVING COUNT(*)>1;

-- 1.4 Students with outstanding amount
SELECT s.admission_no, s.full_name,
       SUM(CASE transaction_type WHEN 'DUE' THEN total_amount ELSE -total_amount END) AS outstanding
FROM students s JOIN fee_transactions t ON t.admission_no=s.admission_no
GROUP BY s.admission_no, s.full_name
HAVING outstanding>0
ORDER BY outstanding DESC;

-- 1.5 Total due per admission number (outstanding balance > 0)
SELECT admission_no,
       SUM(CASE WHEN transaction_type='DUE' THEN total_amount ELSE 0 END) AS total_due,
       SUM(CASE WHEN transaction_type='PAID' THEN total_amount ELSE 0 END) AS total_paid,
       SUM(CASE WHEN transaction_type='CONCESSION' THEN total_amount ELSE 0 END) AS total_concession,
       SUM(CASE transaction_type WHEN 'DUE' THEN total_amount ELSE -total_amount END) AS outstanding_due
FROM fee_transactions
GROUP BY admission_no
HAVING outstanding_due>0
ORDER BY outstanding_due DESC;

-- 1.6 Top 10 students by fee collected
SELECT t.admission_no, s.full_name, SUM(t.total_amount) total_paid
FROM fee_transactions t
JOIN (SELECT DISTINCT admission_no, MIN(full_name) full_name FROM students GROUP BY admission_no) s ON s.admission_no=t.admission_no
WHERE t.transaction_type='PAID' AND t.status='Success'
GROUP BY t.admission_no, s.full_name
ORDER BY total_paid DESC, t.admission_no LIMIT 10;

-- 1.7 Top programs by fee collected (students deduped by admission_no to avoid double counting)
SELECT p.program_name, SUM(t.total_amount) total_collected
FROM fee_transactions t
JOIN (SELECT admission_no, MIN(program_id) program_id FROM students GROUP BY admission_no) s ON s.admission_no=t.admission_no
JOIN programs p ON p.program_id=s.program_id
WHERE t.transaction_type='PAID' AND t.status='Success'
GROUP BY p.program_id, p.program_name
ORDER BY total_collected DESC;

-- 1.8 Parent amount <> sum of child amounts
SELECT t.transaction_id, t.admission_no, t.transaction_type, t.total_amount parent_amount,
       SUM(d.amount) child_amount, t.total_amount-SUM(d.amount) difference
FROM fee_transactions t JOIN fee_transaction_details d ON d.transaction_id=t.transaction_id
GROUP BY t.transaction_id, t.admission_no, t.transaction_type, t.total_amount
HAVING t.total_amount<>SUM(d.amount)
ORDER BY t.transaction_id;

-- 1.9 Parents with no child
SELECT t.* FROM fee_transactions t
LEFT JOIN fee_transaction_details d ON d.transaction_id=t.transaction_id
WHERE d.detail_id IS NULL ORDER BY t.transaction_id;

-- 1.10 Orphan children
SELECT d.* FROM fee_transaction_details d
LEFT JOIN fee_transactions t ON t.transaction_id=d.transaction_id
WHERE t.transaction_id IS NULL ORDER BY d.detail_id;

-- 1.11 Reconciliation report (pre-aggregated on both sides to avoid join fan-out)
SELECT a.admission_no AS `Admission Number`,
       COALESCE(p.txn_count,0) AS `Transaction Count`, COALESCE(p.txn_amount,0) AS `Transaction Amount`,
       COALESCE(c.det_count,0) AS `Detail Count`,      COALESCE(c.det_amount,0) AS `Detail Amount`,
       COALESCE(p.txn_amount,0)-COALESCE(c.det_amount,0) AS `Difference`
FROM (SELECT admission_no FROM fee_transactions UNION SELECT admission_no FROM fee_transaction_details) a
LEFT JOIN (SELECT admission_no, COUNT(*) txn_count, SUM(total_amount) txn_amount FROM fee_transactions GROUP BY admission_no) p ON p.admission_no=a.admission_no
LEFT JOIN (SELECT admission_no, COUNT(*) det_count, SUM(amount) det_amount FROM fee_transaction_details GROUP BY admission_no) c ON c.admission_no=a.admission_no
HAVING `Difference`<>0 OR 1=0   -- remove this HAVING line to see all admissions
ORDER BY a.admission_no;

-- ################ TASK 2 (ADM10025) ################
-- 2.1 Investigation: parents vs children
SELECT t.transaction_id, t.transaction_type, t.total_amount parent_amount,
       COALESCE(SUM(d.amount),0) child_amount, COUNT(d.detail_id) detail_rows,
       t.total_amount-COALESCE(SUM(d.amount),0) missing_amount
FROM fee_transactions t LEFT JOIN fee_transaction_details d ON d.transaction_id=t.transaction_id
WHERE t.admission_no='ADM10025' GROUP BY t.transaction_id, t.transaction_type, t.total_amount;

SELECT * FROM fee_transaction_details WHERE admission_no='ADM10025' ORDER BY detail_id;

-- 2.3 Proof: due computed the way DueCalculationJob does (details) vs from parents
SELECT
 (SELECT SUM(d.amount) FROM fee_transaction_details d JOIN fee_transactions t USING(transaction_id) WHERE t.admission_no='ADM10025' AND t.transaction_type='DUE')
 -(SELECT SUM(d.amount) FROM fee_transaction_details d JOIN fee_transactions t USING(transaction_id) WHERE t.admission_no='ADM10025' AND t.transaction_type='PAID') AS due_from_details,
 (SELECT SUM(total_amount) FROM fee_transactions WHERE admission_no='ADM10025' AND transaction_type='DUE')
 -(SELECT SUM(total_amount) FROM fee_transactions WHERE admission_no='ADM10025' AND transaction_type='PAID') AS due_from_parents;

-- 2.5 Fix (run in a transaction; detail_id 906 assumed free - verify first)
SELECT MAX(detail_id) FROM fee_transaction_details;   -- 905 -> next is 906
START TRANSACTION;
INSERT INTO fee_transaction_details (detail_id, transaction_id, admission_no, fee_head, amount, status)
VALUES (906, 518, 'ADM10025', 'Exam Fee', 5000, 'Success');
-- verify
SELECT t.transaction_id, t.total_amount, SUM(d.amount) child_amount
FROM fee_transactions t JOIN fee_transaction_details d USING(transaction_id)
WHERE t.admission_no='ADM10025' GROUP BY t.transaction_id, t.total_amount;
COMMIT;

-- ################ TASK 3 ################
-- 3.1 Row counts
SELECT 'financial_transaction' tbl, COUNT(*) FROM financial_transaction
UNION ALL SELECT 'financial_transaction_detail', COUNT(*) FROM financial_transaction_detail;
-- 3.2 Load without loss: expected 41 parent / 76 child INSERTs in the file; also parent PK uniqueness
SELECT COUNT(*) parents, COUNT(DISTINCT transaction_id) distinct_ids, SUM(total_amount) total FROM financial_transaction;
SELECT COUNT(*) children, COUNT(DISTINCT detail_id) distinct_ids, SUM(amount) total FROM financial_transaction_detail;
-- 3.3 Amount reconciliation per transaction (FULL outer join emulated with UNION)
CREATE OR REPLACE VIEW v_txn_recon AS
SELECT t.transaction_id, t.admission_no, t.total_amount parent_amount,
       COALESCE(c.child_amount,0) child_amount, t.total_amount-COALESCE(c.child_amount,0) difference,
       CASE WHEN c.transaction_id IS NULL THEN 'NO CHILD' WHEN t.total_amount=c.child_amount THEN 'MATCH' ELSE 'AMOUNT MISMATCH' END result
FROM financial_transaction t
LEFT JOIN (SELECT transaction_id, SUM(amount) child_amount FROM financial_transaction_detail GROUP BY transaction_id) c USING(transaction_id)
UNION ALL
SELECT c.transaction_id, c.admission_no, 0, c.child_amount, -c.child_amount, 'ORPHAN CHILD'
FROM (SELECT transaction_id, MIN(admission_no) admission_no, SUM(amount) child_amount FROM financial_transaction_detail GROUP BY transaction_id) c
WHERE c.transaction_id NOT IN (SELECT transaction_id FROM financial_transaction);
SELECT * FROM v_txn_recon ORDER BY transaction_id;
-- 3.4 Count reconciliation per admission
SELECT a.admission_no, COALESCE(p.cnt,0) parent_count, COALESCE(c.cnt,0) child_distinct_txn_count,
       COALESCE(p.cnt,0)-COALESCE(c.cnt,0) count_diff
FROM (SELECT admission_no FROM financial_transaction UNION SELECT admission_no FROM financial_transaction_detail) a
LEFT JOIN (SELECT admission_no, COUNT(*) cnt FROM financial_transaction GROUP BY admission_no) p USING(admission_no)
LEFT JOIN (SELECT admission_no, COUNT(DISTINCT transaction_id) cnt FROM financial_transaction_detail GROUP BY admission_no) c USING(admission_no)
ORDER BY a.admission_no;
-- 3.5 All mismatches
SELECT * FROM v_txn_recon WHERE result<>'MATCH' ORDER BY transaction_id;
-- 3.6 Parents without child / orphan children
SELECT t.* FROM financial_transaction t LEFT JOIN financial_transaction_detail d USING(transaction_id) WHERE d.detail_id IS NULL;
SELECT d.* FROM financial_transaction_detail d LEFT JOIN financial_transaction t USING(transaction_id) WHERE t.transaction_id IS NULL;
-- 3.7 Final report
SELECT a.admission_no AS `Admission No`,
       COALESCE(p.amt,0) AS `Parent Amount`, COALESCE(c.amt,0) AS `Child Amount`,
       COALESCE(p.amt,0)-COALESCE(c.amt,0) AS `Difference`,
       COALESCE(p.cnt,0) AS `Parent Count`, COALESCE(c.cnt,0) AS `Child Count`,
       CASE WHEN COALESCE(p.amt,0)=COALESCE(c.amt,0) AND COALESCE(p.cnt,0)=COALESCE(c.cnt,0) THEN 'MATCH' ELSE 'MISMATCH' END AS `Status`
FROM (SELECT admission_no FROM financial_transaction UNION SELECT admission_no FROM financial_transaction_detail) a
LEFT JOIN (SELECT admission_no, COUNT(*) cnt, SUM(total_amount) amt FROM financial_transaction GROUP BY admission_no) p USING(admission_no)
LEFT JOIN (SELECT admission_no, COUNT(DISTINCT transaction_id) cnt, SUM(amount) amt FROM financial_transaction_detail GROUP BY admission_no) c USING(admission_no)
ORDER BY a.admission_no;

-- ################ TASK 4 (Scenario A verification) ################
SELECT t.transaction_id, t.total_amount parent_amount, COALESCE(SUM(d.amount),0) child_amount
FROM fee_transactions t LEFT JOIN fee_transaction_details d USING(transaction_id)
WHERE t.admission_no='ADM10025' GROUP BY t.transaction_id, t.total_amount
HAVING parent_amount<>child_amount;
-- Scenario B check: gateway success but no row
SELECT * FROM fee_transactions WHERE admission_no='ADM10089' AND total_amount=12000 AND transaction_date='2025-09-16';

-- ################ TASK 5 ################
SELECT admission_no FROM students WHERE admission_no='ADM10501';  -- verification pattern: query source of truth directly
