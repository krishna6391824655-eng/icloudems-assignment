USE icloud;

-- ################ TASK 2 (ADM10025) ################
-- 2.1 Investigation: parents vs children
-- KYA KARTA HAI: ADM10025 ke har parent ka amount aur uske details ka sum dikhata hai. 518 me 5000 kam dikhega.
SELECT t.transaction_id, t.transaction_type, t.total_amount parent_amount,
       COALESCE(SUM(d.amount),0) child_amount, COUNT(d.detail_id) detail_rows,
       t.total_amount-COALESCE(SUM(d.amount),0) missing_amount
FROM fee_transactions t LEFT JOIN fee_transaction_details d ON d.transaction_id=t.transaction_id
WHERE t.admission_no='ADM10025' GROUP BY t.transaction_id, t.transaction_type, t.total_amount;

SELECT * FROM fee_transaction_details WHERE admission_no='ADM10025' ORDER BY detail_id;

-- 2.3 Proof
-- KYA KARTA HAI: saboot: details se due = 5000, parents se due = 0. Yahi bug hai.: due computed the way DueCalculationJob does (details) vs from parents
SELECT
 (SELECT SUM(d.amount) FROM fee_transaction_details d JOIN fee_transactions t USING(transaction_id) WHERE t.admission_no='ADM10025' AND t.transaction_type='DUE')
 -(SELECT SUM(d.amount) FROM fee_transaction_details d JOIN fee_transactions t USING(transaction_id) WHERE t.admission_no='ADM10025' AND t.transaction_type='PAID') AS due_from_details,
 (SELECT SUM(total_amount) FROM fee_transactions WHERE admission_no='ADM10025' AND transaction_type='DUE')
 -(SELECT SUM(total_amount) FROM fee_transactions WHERE admission_no='ADM10025' AND transaction_type='PAID') AS due_from_parents;

-- 2.5 Fix
-- KYA KARTA HAI: missing Exam Fee 5000 ki detail row wapas daalta hai (transaction me), phir verify karta hai. (run in a transaction; detail_id 906 assumed free - verify first)
SELECT MAX(detail_id) FROM fee_transaction_details;   -- 905 -> next is 906
START TRANSACTION;
INSERT INTO fee_transaction_details (detail_id, transaction_id, admission_no, fee_head, amount, status)
VALUES (906, 518, 'ADM10025', 'Exam Fee', 5000, 'Success');
-- verify
SELECT t.transaction_id, t.total_amount, SUM(d.amount) child_amount
FROM fee_transactions t JOIN fee_transaction_details d USING(transaction_id)
WHERE t.admission_no='ADM10025' GROUP BY t.transaction_id, t.total_amount;
COMMIT;

