USE icloud;

-- ################ TASK 1 ################
-- 1.1 Row counts
-- KYA KARTA HAI: har table me kitni rows hain ginta hai, taaki pata chale data poora load hua.
SELECT 'departments' tbl, COUNT(*) row_count FROM departments
UNION ALL SELECT 'programs', COUNT(*) FROM programs
UNION ALL SELECT 'students', COUNT(*) FROM students
UNION ALL SELECT 'admissions', COUNT(*) FROM admissions
UNION ALL SELECT 'fee_transactions', COUNT(*) FROM fee_transactions
UNION ALL SELECT 'fee_transaction_details', COUNT(*) FROM fee_transaction_details;

-- 1.2 Duplicate admission numbers in students
-- KYA KARTA HAI: jo admission_no 2+ baar students me aaya unhe dhoondhta hai (GROUP BY + HAVING COUNT>1), phir poori rows dikhata hai.
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
-- KYA KARTA HAI: har student ka DUE - PAID - CONCESSION nikalta hai; jinka balance > 0 hai wahi dikhata hai.
SELECT s.admission_no, s.full_name,
       SUM(CASE transaction_type WHEN 'DUE' THEN total_amount ELSE -total_amount END) AS outstanding
FROM students s JOIN fee_transactions t ON t.admission_no=s.admission_no
GROUP BY s.admission_no, s.full_name
HAVING outstanding>0
ORDER BY outstanding DESC;

-- 1.5 Total due per admission number (outstanding balance > 0)
-- KYA KARTA HAI: admission-wise total due, paid, concession aur outstanding alag-alag columns me.
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
-- KYA KARTA HAI: sirf PAID+Success transactions jodkar sabse zyada fee dene wale 10 students.
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
-- KYA KARTA HAI: parent ka total_amount aur uske detail rows ke sum ko compare karta hai; jahan barabar nahi wo dikhata hai.
SELECT t.transaction_id, t.admission_no, t.transaction_type, t.total_amount parent_amount,
       SUM(d.amount) child_amount, t.total_amount-SUM(d.amount) difference
FROM fee_transactions t JOIN fee_transaction_details d ON d.transaction_id=t.transaction_id
GROUP BY t.transaction_id, t.admission_no, t.transaction_type, t.total_amount
HAVING t.total_amount<>SUM(d.amount)
ORDER BY t.transaction_id;

-- 1.9 Parents with no child
-- KYA KARTA HAI: LEFT JOIN se aise parent dhoondhta hai jinki ek bhi detail row nahi hai.
SELECT t.* FROM fee_transactions t
LEFT JOIN fee_transaction_details d ON d.transaction_id=t.transaction_id
WHERE d.detail_id IS NULL ORDER BY t.transaction_id;

-- 1.10 Orphan children
-- KYA KARTA HAI: aisi detail rows jinka parent transaction exist hi nahi karta.
SELECT d.* FROM fee_transaction_details d
LEFT JOIN fee_transactions t ON t.transaction_id=d.transaction_id
WHERE t.transaction_id IS NULL ORDER BY d.detail_id;

-- 1.11 Reconciliation report
-- KYA KARTA HAI: admission-wise parent count/amount aur detail count/amount ek report me, difference ke saath. (pre-aggregated on both sides to avoid join fan-out)
SELECT a.admission_no AS `Admission Number`,
       COALESCE(p.txn_count,0) AS `Transaction Count`, COALESCE(p.txn_amount,0) AS `Transaction Amount`,
       COALESCE(c.det_count,0) AS `Detail Count`,      COALESCE(c.det_amount,0) AS `Detail Amount`,
       COALESCE(p.txn_amount,0)-COALESCE(c.det_amount,0) AS `Difference`
FROM (SELECT admission_no FROM fee_transactions UNION SELECT admission_no FROM fee_transaction_details) a
LEFT JOIN (SELECT admission_no, COUNT(*) txn_count, SUM(total_amount) txn_amount FROM fee_transactions GROUP BY admission_no) p ON p.admission_no=a.admission_no
LEFT JOIN (SELECT admission_no, COUNT(*) det_count, SUM(amount) det_amount FROM fee_transaction_details GROUP BY admission_no) c ON c.admission_no=a.admission_no
HAVING `Difference`<>0 OR 1=0   -- remove this HAVING line to see all admissions
ORDER BY a.admission_no;

