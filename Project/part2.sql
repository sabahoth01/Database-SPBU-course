-- Data normalization
-- Step 1: `employee_base`
CREATE TABLE employee_base (
    emp_id INTEGER NOT NULL REFERENCES employee ON DELETE CASCADE,
    base_id INTEGER NOT NULL REFERENCES base ON DELETE SET NULL,
    PRIMARY KEY (emp_id, base_id)
);
-- Step 2: Migrate existing data (if `base_id` column in `employee` is populated).. миграция данных из employee
INSERT INTO employee_base (emp_id, base_id)
SELECT emp_id, base_id
FROM employee
WHERE base_id IS NOT NULL;
-- Step 3: Remove the `base_id` column from the `employee` table
ALTER TABLE employee
DROP COLUMN base_id;
-- проверка если миграция успешна пошла
SELECT * FROM employee
LIMIT 2;

-- VIEWS
CREATE VIEW employee_details AS -- вернет список сотрудников вместе с информацией о связанных с ними должностях (имя, зарплата  и т.д.).
SELECT
    e.emp_id,
    e.name AS employee_name,
    e.surname,
    e.date_of_birth,
    e.education,
    e.hiring_date,
    p.name AS position_name,
    p.salary_rub,
    p.rank
FROM employee e
JOIN position p ON e.pos_id = p.pos_id;
SELECT * FROM employee_details
         WHERE salary_rub > 80000
         ORDER BY salary_rub
         DESC
         LIMIT 5;

CREATE VIEW mission_summary AS --вернет краткую информацию о каждой миссии, связанном с ней названии кампании, клиенте и используемом транспорте (если таковой имеется).
SELECT
    m.miss_id,
    m.start_date_and_time,
    m.end_date_and_time,
    c.name AS campaign_name,
    c.customer,
    t.name AS transport_name
FROM
    mission m
JOIN
    campaign c ON m.camp_id = c.camp_id
LEFT JOIN
    missions_transport mt ON m.miss_id = mt.miss_id
LEFT JOIN
    transport t ON mt.trans_id = t.trans_id;

SELECT * FROM mission_summary
LIMIT 5;-- ПРОВЕРКА

-- MATERIALIZED VIEW
CREATE MATERIALIZED VIEW campaign_profit AS --сохраняет результат запроса, который вычисляет прибыль от каждой кампании (доходы - расходы).
SELECT
    camp_id,
    name,
    customer,
    earning,
    spending,
    earning - spending AS profit
FROM campaign;
--обновляет данные в материализованном представлении campaign_profit.
REFRESH MATERIALIZED VIEW campaign_profit;
-- Проверка
SELECT * FROM campaign_profit
ORDER BY profit
DESC
LIMIT 2;

-- CTE
WITH employee_health_summary AS ( -- извлекает основные медицинские данные (рост, вес, группа крови) из таблиц employee и medical_card, объединяя их с помощью emp_id.
    SELECT
        e.emp_id,
        e.name,
        e.surname,
        m.height_cm,
        m.weight_kg,
        m.diseases,
        m.gender,
        m.blood
    FROM employee e
    JOIN medical_card m ON e.emp_id = m.emp_id
)
SELECT
    name,
    surname,
    height_cm,
    weight_kg,
    blood,
    diseases,
    gender,
    CASE
        WHEN height_cm < 160 THEN 'Short'
        WHEN height_cm BETWEEN 160 AND 180 THEN 'Average'
        WHEN height_cm > 180 THEN 'Tall'
    END AS height_category,
    CASE
        WHEN weight_kg < 60 THEN 'Underweight'
        WHEN weight_kg BETWEEN 60 AND 150 THEN 'Normal weight'
        WHEN weight_kg > 150 THEN 'Overweight'
    END AS weight_category
FROM employee_health_summary;

WITH transport_availability AS ( -- возвращает список названий транспортных средств со статусом их доступности
    SELECT
        t.trans_id,
        t.name AS transport_name,
        t.status,
        m.start_date_and_time,
        CURRENT_TIMESTAMP AS "current_time"
    FROM transport t
    LEFT JOIN missions_transport mt ON t.trans_id = mt.trans_id
    LEFT JOIN mission m ON mt.miss_id = m.miss_id
)
SELECT
    transport_name,
    CASE
        WHEN status = 'OUT_OF_USE' OR status = 'NOT_MAINTAINED' THEN 'Not Available'
        WHEN start_date_and_time > CURRENT_TIMESTAMP THEN 'Available'
        ELSE 'In Use'
    END AS availability_status
FROM transport_availability;

-- TEMP_TABLE
CREATE TEMPORARY TABLE temp_employee_availability AS -- Временная таблица для проверки доступности сотрудников в зависимости от их назначенных заданий. Может использоваться для просмотра того, кто может быть назначен на новое задание.
SELECT
    e.emp_id,
    e.name AS employee_name,
    e.surname,
    CASE
        WHEN m.miss_id IS NULL THEN 'Available'
        ELSE 'Not Available'
    END AS availability_status
FROM employee e
LEFT JOIN missions_emp me ON e.emp_id = me.emp_id
LEFT JOIN mission m ON me.miss_id = m.miss_id
WHERE m.end_date_and_time <= CURRENT_TIMESTAMP OR m.miss_id IS NULL;
-- проверка
SELECT * FROM temp_employee_availability
LIMIT 5;

-- RECURSIVE
WITH RECURSIVE employee_mission_hierarchy AS ( --извлекает все задания, назначенные конкретному сотруднику (начиная с emp_id сотрудника = 1).
    -- Base case: Start from a specific employee
    SELECT
        e.emp_id,
        e.name AS employee_name,
        e.surname AS employee_surname,
        m.miss_id,
        m.start_date_and_time,
        m.end_date_and_time
    FROM employee e
    JOIN missions_emp me ON e.emp_id = me.emp_id
    JOIN mission m ON me.miss_id = m.miss_id
    WHERE e.emp_id = 1  -- Start with an employee (e.g., employee_id = 1)
    UNION ALL
    -- Recursive case: Find all missions this employee was assigned to
    SELECT
        e.emp_id,
        e.name AS employee_name,
        e.surname AS employee_surname,
        m.miss_id,
        m.start_date_and_time,
        m.end_date_and_time
    FROM employee e
    JOIN missions_emp me ON e.emp_id = me.emp_id
    JOIN mission m ON me.miss_id = m.miss_id
    JOIN employee_mission_hierarchy emh ON m.miss_id = emh.miss_id  -- Recursively find missions
)
SELECT
    employee_name,
    employee_surname,
    miss_id,
    start_date_and_time,
    end_date_and_time
FROM employee_mission_hierarchy;

WITH RECURSIVE weapon_mission_path AS ( -- отслеживает использование определенного оружия (начиная с weapon_id = 1) в миссиях.
    -- Base case: Start from a specific weapon
    SELECT
        w.weapon_id,
        w.name AS weapon_name,
        m.miss_id,
        m.start_date_and_time,
        m.end_date_and_time
    FROM weapon w
    JOIN equip_weapon ew ON w.weapon_id = ew.weapon_id
    JOIN missions_emp me ON ew.equip_id = me.emp_id
    JOIN mission m ON me.miss_id = m.miss_id
    WHERE w.weapon_id = 1  -- For example, start from a specific weapon
    UNION ALL
    -- Recursive case: Find the next mission where this weapon is used
    SELECT
        w.weapon_id,
        w.name AS weapon_name,
        m.miss_id,
        m.start_date_and_time,
        m.end_date_and_time
    FROM weapon w
    JOIN equip_weapon ew ON w.weapon_id = ew.weapon_id
    JOIN missions_emp me ON ew.equip_id = me.emp_id
    JOIN mission m ON me.miss_id = m.miss_id
    JOIN weapon_mission_path wmp ON m.miss_id = wmp.miss_id  -- Recursively find related missions
)
SELECT
    weapon_name,
    miss_id,
    start_date_and_time,
    end_date_and_time
FROM weapon_mission_path;

-- INDEXES
CREATE INDEX idx_employee_base_emp_id ON employee_base USING HASH(emp_id);  --hash index
CREATE INDEX idx_employee_base_base_id ON employee_base USING HASH(base_id);
CREATE INDEX idx_employee_pos_id ON employee USING HASH(pos_id);
CREATE INDEX idx_employee_emp_id ON employee USING HASH(emp_id);
CREATE INDEX idx_employee_emp_name ON employee(name); --b-tree index by default
CREATE INDEX idx_employee_emp_surname ON employee(surname);
CREATE INDEX idx_position_pos_id ON position USING HASH(pos_id);
CREATE INDEX idx_mission_camp_id ON mission USING HASH(camp_id);
CREATE INDEX idx_mission_start_date ON mission(start_date_and_time);
CREATE INDEX idx_mission_end_date ON mission(end_date_and_time);
CREATE INDEX idx_mission_miss_id ON mission USING HASH(miss_id);
CREATE INDEX idx_campaign_camp_id ON campaign USING HASH(camp_id);
CREATE INDEX idx_missions_transport_miss_id ON missions_transport USING HASH(miss_id);
CREATE INDEX idx_transport_trans_id ON transport USING HASH(trans_id);
CREATE INDEX idx_medical_card_emp_id ON medical_card USING HASH(emp_id);
CREATE INDEX idx_equip_weapon_weapon_id ON equip_weapon USING HASH(weapon_id);
CREATE INDEX idx_employee_weapon_name ON weapon(name);

--EXPLAIN ANALYZE
EXPLAIN ANALYZE SELECT * FROM employee_details
WHERE salary_rub > 80000
ORDER BY salary_rub
DESC
LIMIT 5;

-- index usage per table//отслеживает использование определенного оружия (начиная с weapon_id = 1) в миссиях.
SELECT relname , indexrelname , idx_scan , idx_tup_read , idx_tup_fetch
FROM pg_stat_user_indexes
WHERE schemaname = 'public' and
  relname in ('campaign');

VACUUM;