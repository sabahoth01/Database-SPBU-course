-- A. Functions
-- 1. Function to Check Employee Qualifications
CREATE OR REPLACE FUNCTION check_qualifications(p_emp_id INT, p_position_name TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    employee_position_name TEXT;
BEGIN
    SELECT pos.name INTO employee_position_name  -- Retrieve the position name for the given employee
    FROM position pos
    JOIN employee e ON e.pos_id = pos.pos_id
    WHERE e.emp_id = p_emp_id;
    IF employee_position_name = p_position_name THEN -- If the employee's position matches the given position name, return TRUE
        RETURN TRUE;
    ELSE
        RETURN FALSE;
    END IF;
END;
$$ LANGUAGE plpgsql;
--test
SELECT check_qualifications(1, 'Security'); -- Returns TRUE or FALSE based on employee qualifications.

-- 2. Function to get unmarried, available, and experienced employees (both unmarried and married)
CREATE OR REPLACE FUNCTION get_experienced_available_employees()
RETURNS TABLE (
    emp_id INT,
    employee_name VARCHAR,
    employee_surname VARCHAR,
    availability_status VARCHAR,
    missions_count INT,
    is_married BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        e.emp_id,
        e.name AS employee_name,
        e.surname AS employee_surname,
        CASE
            WHEN COUNT(m.miss_id) = 0 THEN 'Available'  -- If no missions or all missions ended, employee is available
            ELSE 'Not Available'
        END::VARCHAR AS availability_status,
        COUNT(m.miss_id)::INTEGER AS missions_count,
        e.is_married  -- Add marital status to the result
    FROM employee e
    LEFT JOIN missions_emp me ON e.emp_id = me.emp_id
    LEFT JOIN mission m ON me.miss_id = m.miss_id AND (m.end_date_and_time <= CURRENT_TIMESTAMP OR m.miss_id IS NULL)  -- Ensure the mission has ended or employee has no mission
    GROUP BY e.emp_id, e.name, e.surname, e.is_married  -- Group by employee details (no need to group by mission details)
    HAVING COUNT(m.miss_id) = 0 OR MAX(m.end_date_and_time) <= CURRENT_TIMESTAMP  -- Ensure the employee is available (either no missions or all missions have ended)
    ORDER BY e.is_married,        -- Unmarried employees first
             missions_count DESC, -- Experienced (mission-count) employees first
             availability_status DESC;  -- Available employees first
END;
$$ LANGUAGE plpgsql;

-- B. Triggers
--1. Trigger Function to check medical eligibility for all tasks
CREATE OR REPLACE FUNCTION check_employee_medical_eligibility()
RETURNS TRIGGER AS $$
BEGIN
    IF EXISTS (-- Ensure employee has no medical diseases
        SELECT 1
        FROM medical_card m
        WHERE m.emp_id = NEW.emp_id
          AND (m.diseases IS DISTINCT FROM 'none' AND m.diseases IS NOT NULL) -- Check diseases
    ) THEN
        RAISE EXCEPTION 'Employee does not meet the medical requirements for being sent to any mission';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
-- Trigger to enforce medical eligibility check when assigning to any task
CREATE TRIGGER employee_medical_check
BEFORE INSERT ON missions_emp
FOR EACH ROW
EXECUTE FUNCTION check_employee_medical_eligibility();
--test
INSERT INTO missions_emp(miss_id, emp_id) VALUES
(16,2);

--2. close base if it has no employees
CREATE OR REPLACE FUNCTION close_base_if_empty()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS ( -- Check if any employee is still assigned to the base
        SELECT 1
        FROM employee_base eb
        WHERE eb.base_id = OLD.base_id
    ) THEN
        UPDATE base -- If no employees are assigned, close the base
        SET status = 'CLOSED'
        WHERE base_id = OLD.base_id;
    END IF;
    RETURN OLD;  -- Return OLD because it's an AFTER DELETE trigger
END;
$$ LANGUAGE plpgsql;
-- Trigger to check and close the base when an employee is removed from it
CREATE TRIGGER close_base_trigger
AFTER DELETE ON employee_base
FOR EACH ROW
EXECUTE FUNCTION close_base_if_empty();

-- 3. open base if it has at least one employee
CREATE OR REPLACE FUNCTION open_base_if_not_empty()
RETURNS TRIGGER AS $$
BEGIN
    IF EXISTS ( -- Check if there is at least one employee assigned to the base
        SELECT 1
        FROM employee_base eb
        WHERE eb.base_id = NEW.base_id
    ) THEN
        UPDATE base  -- If at least one employee is assigned, open the base
        SET status = 'OPEN'
        WHERE base_id = NEW.base_id;
    END IF;
    RETURN NEW;  -- Return NEW because it's an AFTER INSERT trigger
END;
$$ LANGUAGE plpgsql;
-- Trigger to check and open the base when an employee is added to it
CREATE TRIGGER open_base_trigger
AFTER INSERT ON employee_base
FOR EACH ROW
EXECUTE FUNCTION open_base_if_not_empty();

--4. Trigger for campaigns to automatically refresh materialized view
-- Refresh the materialized view whenever a campaign is inserted, updated, or deleted
CREATE OR REPLACE FUNCTION refresh_campaign_profit()
RETURNS TRIGGER AS $$
BEGIN
    REFRESH MATERIALIZED VIEW campaign_profit;
    RETURN NULL;  -- No need to modify the inserted/updated/deleted row
END;
$$ LANGUAGE plpgsql;
-- Create the trigger for INSERT, UPDATE, DELETE events on the campaign table
CREATE TRIGGER campaign_change_trigger
AFTER INSERT OR UPDATE OR DELETE
ON campaign
FOR EACH STATEMENT
EXECUTE FUNCTION refresh_campaign_profit();

--5. prevent overlap of mission(one employee can not be sent to 2 different missions in the same time)
CREATE OR REPLACE FUNCTION check_periods_of_emp_missions() RETURNS trigger AS $$
DECLARE
    start_time TIMESTAMP;
    end_time TIMESTAMP;
BEGIN
    SELECT start_date_and_time, end_date_and_time INTO start_time, end_time -- Retrieve the start and end times for the mission being assigned to the employee
    FROM mission
    WHERE miss_id = NEW.miss_id;
    IF EXISTS ( -- Check if the employee is already assigned to a mission that overlaps with the new one
        SELECT 1
        FROM mission m
        JOIN missions_emp me ON m.miss_id = me.miss_id
        WHERE me.emp_id = NEW.emp_id
          AND (m.start_date_and_time, m.end_date_and_time) OVERLAPS (start_time, end_time)
    ) THEN
        RAISE EXCEPTION 'This employee cannot be assigned to a mission as they were on another mission at the time';
    END IF;
    RETURN NEW;-- Allow the insert if no overlap is found
END;
$$ LANGUAGE plpgsql;
--trigger
CREATE TRIGGER check_emp_mission_period
BEFORE INSERT ON missions_emp
FOR EACH ROW
EXECUTE FUNCTION check_periods_of_emp_missions();

--6. Function to update the transport status after an inspection
CREATE OR REPLACE FUNCTION update_transport_status_after_inspection() RETURNS trigger AS $$
BEGIN
    IF NEW.remarks ILIKE '%damage%' OR NEW.remarks ILIKE '%serious%' OR NEW.remarks ILIKE '%accident%' THEN -- Check if the remarks column contains keywords indicating serious damage or accidents

        UPDATE transport -- If any of these keywords are found, set transport status to OUT_OF_USE
        SET status = 'OUT_OF_USE'
        WHERE trans_id = NEW.trans_id;
    ELSIF NEW.result = 'PASS' THEN
        UPDATE transport -- If inspection passed, mark transport as MAINTAINED, If inspection failed, mark transport as NOT_MAINTAINED
        SET status = 'MAINTAINED'
        WHERE trans_id = NEW.trans_id;
    ELSIF NEW.result = 'FAILED' THEN
        UPDATE transport
        SET status = 'NOT_MAINTAINED'
        WHERE trans_id = NEW.trans_id;
    ELSIF NEW.result = 'PENDING' THEN -- If inspection is pending, mark transport as NEED_VERIFICATION
        UPDATE transport
        SET status = 'NEED_VERIFICATION'
        WHERE trans_id = NEW.trans_id;
    END IF;
    RETURN NEW; -- Return the new inspection record
END;
$$ LANGUAGE plpgsql;
-- Trigger to call the function after an inspection is inserted
CREATE TRIGGER transport_status_after_inspection
AFTER INSERT ON inspection
FOR EACH ROW
EXECUTE FUNCTION update_transport_status_after_inspection();

-- 7. Function to check transport status before adding to mission
CREATE OR REPLACE FUNCTION check_transport_status_before_mission() RETURNS trigger AS $$
BEGIN
    IF NOT EXISTS ( -- Check if the transport status is either VERIFIED or MAINTAINED
        SELECT 1
        FROM transport
        WHERE trans_id = NEW.trans_id
          AND status IN ('VERIFIED', 'MAINTAINED')  -- Only allow VERIFIED or MAINTAINED status
    ) THEN
        RAISE EXCEPTION 'Transport cannot be added to the mission because its status is not VERIFIED or MAINTAINED.';
    END IF;
    RETURN NEW; -- If the status is correct, allow the insert
END;
$$ LANGUAGE plpgsql;
-- Trigger to call the function before adding transport to a mission
CREATE TRIGGER check_transport_status_before_addition
BEFORE INSERT ON missions_transport
FOR EACH ROW
EXECUTE FUNCTION check_transport_status_before_mission();

-- C. transaction
-- 1. Assign an employee to a mission with different checking:
BEGIN;
-- Step 1: Check if the employee is medically eligible for the mission
-- This is handled by the trigger 'check_employee_medical_eligibility' when inserting the record into missions_emp

-- Step 2: Check if the employee is available for the mission (overlap check handled by trigger 'check_emp_mission_period')
-- No action needed here since it's enforced by the trigger.

-- Step 3: Check if the transport assigned to the mission is in a suitable status (MAINTAINED or VERIFIED)
DO $$
DECLARE
    transport_valid BOOLEAN;
BEGIN
    SELECT EXISTS ( -- Check transport status before assignment
        SELECT 1
        FROM transport
        WHERE trans_id = 3  -- Replace with the actual transport ID
          AND status IN ('VERIFIED', 'MAINTAINED')
    ) INTO transport_valid;
    IF NOT transport_valid THEN -- If the result is FALSE, raise an exception
        RAISE EXCEPTION 'Transport is not in an acceptable status.';
    END IF;
END $$;

INSERT INTO missions_emp(miss_id, emp_id)-- Step 4: Assign the employee to the mission
VALUES (16, 11);
INSERT INTO missions_transport(miss_id, trans_id)-- Step 5: Assign transport to the mission (if the status is appropriate)
VALUES (16, 3);

CALL update_campaign_status_to_finished();-- Step 6: Update campaign status to FINISHED if all associated missions have ended

COMMIT;

--2. Like the first transaction but need to check qualification(for example want to add an employee who is a pilot to the mission)
BEGIN;

-- Step 1: Check if the employee is qualified for the mission
DO $$
DECLARE
    emp_qualified BOOLEAN;
BEGIN
    emp_qualified := check_qualifications(13, 'Pilot');-- Check qualifications using the function, which returns a boolean
    IF NOT emp_qualified THEN -- If the result is FALSE, raise an exception
        RAISE EXCEPTION 'Employee is not qualified for the position.';
    END IF;
END $$;
-- Step 2: Check if the employee is medically eligible for the mission
-- This is handled by the trigger 'check_employee_medical_eligibility' when inserting the record into missions_emp

-- Step 3: Check if the employee is available for the mission (overlap check handled by trigger 'check_emp_mission_period')
-- No action needed here since it's enforced by the trigger.

-- Step 4: Check if the transport assigned to the mission is in a suitable status (MAINTAINED or VERIFIED)
DO $$
DECLARE
    transport_valid BOOLEAN;
BEGIN
    SELECT EXISTS (-- Check transport status before assignment
        SELECT 1
        FROM transport
        WHERE trans_id = 3  -- Replace with the actual transport ID
          AND status IN ('VERIFIED', 'MAINTAINED')
    ) INTO transport_valid;
    IF NOT transport_valid THEN-- If the result is FALSE, raise an exception
        RAISE EXCEPTION 'Transport is not in an acceptable status.';
    END IF;
END $$;

INSERT INTO missions_emp(miss_id, emp_id)-- Step 5: Assign the employee to the mission
VALUES (20, 13);
INSERT INTO missions_transport(miss_id, trans_id)-- Step 6: Assign transport to the mission (if the status is appropriate)
VALUES (20, 3); -- Replace with actual transport ID

CALL update_campaign_status_to_finished();-- Step 7: Update campaign status to FINISHED if all associated missions have ended

COMMIT;

--D. Procedure
-- Update execution status to 'FINISHED' for campaigns where all associated missions have ended
CREATE OR REPLACE PROCEDURE update_campaign_status_to_finished()
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE campaign c
    SET execution_status = 'FINISHED'
    WHERE c.camp_id IN (
        SELECT m.camp_id
        FROM mission m
        WHERE m.legal_status = TRUE
        GROUP BY m.camp_id
        HAVING COUNT(*) = COUNT(CASE WHEN m.end_date_and_time < CURRENT_TIMESTAMP THEN 1 END)
    )
    AND c.execution_status != 'FINISHED';  -- Only update if not already finished
    RAISE NOTICE 'Campaign statuses updated to FINISHED for campaigns with all missions completed.';
END;
$$;
call update_campaign_status_to_finished();

--updates
-- Creating or updating the temporary table to include unmarried, available, experienced employees, and their mission count and marital status
CREATE TEMPORARY TABLE temp_employee_availability AS
SELECT
    emp_id,
    employee_name,
    employee_surname,
    availability_status,
    missions_count,  -- Include the mission count in the temporary table
    is_married       -- Include the marital status in the temporary table
FROM get_experienced_available_employees()  -- Use the function to fetch the data
ORDER BY is_married,               -- Sort unmarried employees first
         missions_count DESC,      -- Sort by mission count (most experienced first)
         availability_status DESC, -- Sort by availability (Available first)
         emp_id;  -- Final sorting by emp_id for consistency

-- added index
CREATE INDEX mission_period ON mission USING btree(start_date_and_time, end_date_and_time);
