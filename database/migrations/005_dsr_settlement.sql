-- DSR delivery + settlement review (additive; existing rows unchanged).
USE `happybasic`;

-- Partner can send a submitted settlement back to the DSR with a note
ALTER TABLE `trip_settlements`
    MODIFY `status` ENUM('submitted', 'approved', 'returned') NOT NULL DEFAULT 'submitted',
    ADD COLUMN `review_note` VARCHAR(255) NULL AFTER `status`;
