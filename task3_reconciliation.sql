USE icloud;

-- ################ TASK 3 ################
-- 3.1 Row counts
SELECT 'financial_transaction' tbl, COUNT(*) FROM financial_transaction
UNION ALL SELECT 'financial_transaction_detail', COUNT(*) FROM financial_transaction_detail;
-- 3.2 Load without loss: expected 41 parent / 76 child INSERTs in the file; also parent PK uniqueness
SELECT COUNT(*) parents, COUNT(DISTINCT transaction_id) distinct_ids, SUM(total_amount) total FROM financial_transaction;
SELECT COUNT(*) children, COUNT(DISTINCT detail_id) distinct_ids, SUM(amount) total FROM financial_transaction_detail;
-- 3.3 Amount reconciliation
-- KYA KARTA HAI: har transaction ka parent vs child amount, aur result: MATCH / AMOUNT MISMATCH / NO CHILD / ORPHAN CHILD. per transaction (FULL outer join emulated with UNION)
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
-- KYA KARTA HAI: admission-wise parent transactions ki ginti vs child ke distinct transaction_id ki ginti.
SELECT a.admission_no, COALESCE(p.cnt,0) parent_count, COALESCE(c.cnt,0) child_distinct_txn_count,
       COALESCE(p.cnt,0)-COALESCE(c.cnt,0) count_diff
FROM (SELECT admission_no FROM financial_transaction UNION SELECT admission_no FROM financial_transaction_detail) a
LEFT JOIN (SELECT admission_no, COUNT(*) cnt FROM financial_transaction GROUP BY admission_no) p USING(admission_no)
LEFT JOIN (SELECT admission_no, COUNT(DISTINCT transaction_id) cnt FROM financial_transaction_detail GROUP BY admission_no) c USING(admission_no)
ORDER BY a.admission_no;
-- 3.5 All mismatches
-- KYA KARTA HAI: sirf wahi transactions jo MATCH nahi hain.
SELECT * FROM v_txn_recon WHERE result<>'MATCH' ORDER BY transaction_id;
-- 3.6 Parents without child
-- KYA KARTA HAI: pehli query parent bina child, doosri child bina parent. / orphan children
SELECT t.* FROM financial_transaction t LEFT JOIN financial_transaction_detail d USING(transaction_id) WHERE d.detail_id IS NULL;
SELECT d.* FROM financial_transaction_detail d LEFT JOIN financial_transaction t USING(transaction_id) WHERE t.transaction_id IS NULL;
-- 3.7 Final report
-- KYA KARTA HAI: final report: Parent/Child amount, Difference, counts aur Status (MATCH/MISMATCH).
SELECT a.admission_no AS `Admission No`,
       COALESCE(p.amt,0) AS `Parent Amount`, COALESCE(c.amt,0) AS `Child Amount`,
       COALESCE(p.amt,0)-COALESCE(c.amt,0) AS `Difference`,
       COALESCE(p.cnt,0) AS `Parent Count`, COALESCE(c.cnt,0) AS `Child Count`,
       CASE WHEN COALESCE(p.amt,0)=COALESCE(c.amt,0) AND COALESCE(p.cnt,0)=COALESCE(c.cnt,0) THEN 'MATCH' ELSE 'MISMATCH' END AS `Status`
FROM (SELECT admission_no FROM financial_transaction UNION SELECT admission_no FROM financial_transaction_detail) a
LEFT JOIN (SELECT admission_no, COUNT(*) cnt, SUM(total_amount) amt FROM financial_transaction GROUP BY admission_no) p USING(admission_no)
LEFT JOIN (SELECT admission_no, COUNT(DISTINCT transaction_id) cnt, SUM(amount) amt FROM financial_transaction_detail GROUP BY admission_no) c USING(admission_no)
ORDER BY a.admission_no;

