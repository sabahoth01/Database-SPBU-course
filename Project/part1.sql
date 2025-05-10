-- CREATE DATABASE "securityOrganisation"
--     WITH
--     OWNER = postgres
--     ENCODING = 'UTF8'
--     STRATEGY = WAL_LOG -- стандартный метод, используемый в субд для обеспечения целостности и долговечности данных.
--     TABLESPACE = pg_default
--     CONNECTION LIMIT = -1
--     IS_TEMPLATE = False;
--
-- COMMENT ON DATABASE "securityOrganisation"
--     IS 'Database for final project on private security organisation , SPBU first semester, 2024';

-- помните, что типы перечислений(ENUM) чувствительны к регистру символов.
CREATE TYPE base_status AS ENUM ('OPEN', 'CLOSED');
CREATE TABLE base
(
    base_id  SERIAL PRIMARY KEY,
    location TEXT NOT NULL,
    status   base_status NOT NULL
);

CREATE TABLE employee_base
(
    emp_id  integer not null references employee on delete cascade,
    base_id integer not null references base on delete set null,
    primary key (emp_id, base_id)
);

-- Meal, Ready-to-Eat (MRE) : Блюдо, готовое к употреблению (MRE)
-- это автономный индивидуальный военный рацион Соединенных Штатов, используемый Вооруженными силами Соединенных Штатов и Министерством обороны.
CREATE TABLE mre
(
    mre_id         SERIAL PRIMARY KEY,
    breakfast      TEXT     NOT NULL,
    lunch          TEXT     NOT NULL,
    dinner         TEXT     NOT NULL,
    food_additives TEXT,
    kkal           SMALLINT NOT NULL CHECK (kkal >= 3000 AND kkal <= 5000),
    proteins       SMALLINT NOT NULL CHECK (proteins >= 50 AND proteins <= 200),
    fats           SMALLINT NOT NULL CHECK (fats >= 44 AND fats <= 100 ),
    carbohydrate   SMALLINT NOT NULL CHECK (carbohydrate >= 250 AND carbohydrate <= 400)
);

CREATE TABLE equipment
(
    equip_id      SERIAL PRIMARY KEY,
    camouflage    VARCHAR(100),
    communication VARCHAR(100),
    intelligence  VARCHAR(100),
    medical       TEXT,
    mre_id        INTEGER NOT NULL REFERENCES mre ON DELETE RESTRICT, --foreign key
    extra         VARCHAR(50)
);

CREATE TYPE force_category AS ENUM ('GF', 'NAVY', 'AF');

--numeric(10,2):Точность (10): указывает общее количество значащих цифр, которые могут быть сохранены в этом столбце. В этом случае зарплата может содержать до 10 цифр.
--Шкала (2): Указывает количество цифр, которые могут быть сохранены справа от десятичной точки. Здесь это означает, что для обозначения дробной части (центов) можно использовать 2 цифры.

CREATE TABLE position
(
    pos_id   SERIAL PRIMARY KEY,
    name     VARCHAR(255)       NOT NULL,
    salary_rub   NUMERIC(10, 2) NOT NULL CHECK (salary_rub >= 50000),
    rank     VARCHAR(100),
    equip_id INTEGER   REFERENCES equipment ON DELETE SET NULL, --foreign key
    forces   force_category
);

CREATE TABLE employee
(
    emp_id        SERIAL PRIMARY KEY,
    name          VARCHAR(255)    NOT NULL,
    surname       VARCHAR(255)    NOT NULL,
    date_of_birth DATE    NOT NULL CHECK (DATE_PART('year', AGE(date_of_birth)) >= 18),
    CHECK (DATE_PART('year', AGE(date_of_birth)) <= 60),   -- Maximum age 60
    education     TEXT,
    hiring_date   DATE NOT NULL DEFAULT CURRENT_DATE,
    pos_id        INTEGER NOT NULL REFERENCES position ON DELETE RESTRICT, --foreign key
    is_married    BOOLEAN NOT NULL
);

CREATE TYPE blood_type AS ENUM ('A', 'B', 'O','AB','AO','BO');
CREATE TABLE medical_card
(
    med_id    SERIAL PRIMARY KEY,
    emp_id    INTEGER  NOT NULL REFERENCES employee ON DELETE CASCADE, --foreign key
    height_cm SMALLINT NOT NULL CHECK (height_cm >= 150 AND height_cm <= 250),
    weight_kg SMALLINT NOT NULL CHECK (weight_kg >= 50 AND weight_kg <= 100),
    diseases  TEXT,
    blood     blood_type  NOT NULL, -- AA, AO, AB,
    gender    VARCHAR(1)  NOT NULL -- M OR F
);

CREATE TABLE weapon
(
    weapon_id        SERIAL PRIMARY KEY,
    name             VARCHAR(255) NOT NULL,
    type             VARCHAR(255) NOT NULL,
    caliber          REAL CHECK (caliber > 0),
    rate_of_fire     SMALLINT CHECK (rate_of_fire > 0),
    sighting_range_m SMALLINT CHECK (sighting_range_m > 0)
);

CREATE TYPE ex_status AS ENUM ('NOT_STARTED', 'STARTED', 'ON_GOING','PENDING','FINISHED');
CREATE TABLE campaign
(
    camp_id          SERIAL PRIMARY KEY,
    name             VARCHAR(255)           NOT NULL,
    customer         VARCHAR(255)           NOT NULL,
    earning          NUMERIC(11, 2) NOT NULL CHECK (earning >= 0),
    spending         NUMERIC(11, 2) NOT NULL CHECK (spending >= 0),
    execution_status ex_status
);

CREATE TABLE mission
(
    miss_id             SERIAL PRIMARY KEY,
    camp_id             INTEGER NOT NULL REFERENCES campaign ON DELETE CASCADE,
    start_date_and_time TIMESTAMP,
    end_date_and_time   TIMESTAMP,
    legal_status        BOOLEAN NOT NULL,
    departure_location  VARCHAR(255),
    arrival_location    VARCHAR(255),
    enemies             TEXT
);

CREATE TYPE trans_status AS ENUM ('VERIFIED', 'NEED_VERIFICATION', 'MAINTAINED','NOT_MAINTAINED','OUT_OF_USE');
CREATE TABLE transport
(
    trans_id SERIAL PRIMARY KEY,
    name     VARCHAR(100) NOT NULL,
    type     VARCHAR(100) NOT NULL,
    status   trans_status NOT NULL
);

CREATE TABLE equip_weapon
(
    equip_id  INTEGER NOT NULL REFERENCES equipment,
    weapon_id INTEGER NOT NULL REFERENCES weapon,
    PRIMARY KEY (equip_id, weapon_id)
);

CREATE TABLE missions_transport
(
    miss_id  INTEGER NOT NULL REFERENCES mission,
    trans_id INTEGER NOT NULL REFERENCES transport,
    PRIMARY KEY (miss_id, trans_id)
);

CREATE TABLE inspection
(
    inspection_id           serial primary key,
    inspector_fullname      varchar(255)              not null,
    trans_id                integer                   not null  references transport,
    inspection_date         date default CURRENT_DATE not null,
    inspection_type         varchar(100)              not null,
    result                  inspection_result         not null,
    repair_recommendations  text,
    status_after_inspection trans_status,
    remarks                 text,
    unique (inspector_fullname, trans_id, inspection_date)
);

CREATE TABLE missions_emp
(
    miss_id INTEGER NOT NULL REFERENCES mission,
    emp_id  INTEGER NOT NULL REFERENCES employee,
    PRIMARY KEY (miss_id, emp_id)
);

-- -- Good Data Population// Заполнение таблицы
--
-- -- Insert into base
-- INSERT INTO base (location, status) VALUES
-- ('Base Alpha', 'OPEN'),
-- ('Base Bravo', 'CLOSED');
--
-- -- Insert into mre
-- INSERT INTO mre (breakfast, lunch, dinner, food_additives, kkal, proteins, fats, carbohydrate) VALUES
-- ('Oatmeal', 'Chicken Stew', 'Beef Jerky', 'None', 3500, 60, 50, 300),
-- ('Pasta', 'Tuna Salad', 'Fruit Mix', 'None', 4000, 70, 60, 350);
--
-- -- Insert into equipment
-- INSERT INTO equipment (camouflage, communication, intelligence, medical, mre_id, extra) VALUES
-- ('Green', 'Radio', 'Drone', 'First Aid Kit', 1, 'None'),
-- ('Desert', 'Satellite Phone', 'Recon', 'Med Kit', 2, 'None');
--
-- -- Insert into position
-- INSERT INTO position (name, salary_rub, rank, equip_id, forces) VALUES
-- ('Rifleman', 60000, 'Private', 1, 'GF'),
-- ('Sniper', 80000, 'Corporal', 2, 'NAVY');
--
-- -- Insert into employee
-- INSERT INTO employee (name, surname, date_of_birth, education, hiring_date, pos_id, is_married, base_id) VALUES
-- ('John', 'Doe', '1990-01-01', 'High School', '2023-01-01', 1, TRUE, 1),
-- ('Jane', 'Smith', '1985-05-15', 'Bachelor', '2023-02-01', 2, FALSE, 2);
--
-- -- Insert into medical_card
-- INSERT INTO medical_card (emp_id, height_cm, weight_kg, diseases, blood, gender) VALUES
-- (1, 180, 75, 'None', 'A', 'M'),
-- (2, 165, 60, 'None', 'B', 'F');
--
-- -- Insert into weapon
-- INSERT INTO weapon (name, type, caliber, rate_of_fire, sighting_range_m) VALUES
-- ('M4 Carbine', 'Rifle', 5.56, 700, 600),
-- ('M24 Sniper', 'Sniper Rifle', 7.62, 40, 800);
--
-- -- Insert into campaign
-- INSERT INTO campaign (name, customer, earning, spending, execution_status) VALUES
-- ('Operation Alpha', 'Department of Defense', 1000000.00, 500000.00, 'FINISHED'),
-- ('Operation Bravo', 'NATO', 2000000.00, 1500000.00, 'ON_GOING');
--
-- -- Insert into mission
-- INSERT INTO mission (camp_id, start_date_and_time, end_date_and_time, legal_status, departure_location, arrival_location, enemies) VALUES
-- (1, '2023-01-10 08:00:00', '2023-01-15 18:00:00', TRUE, 'Base Alpha', 'Base Bravo', 'None'),
-- (2, '2023-02-20 09:00:00', '2023-02-25 17:00:00', TRUE, 'Base Bravo', 'Base Alpha', 'Enemy Forces');
--
-- -- Insert into transport
-- INSERT INTO transport (name, type, status) VALUES
-- ('Transport Truck', 'Ground', 'VERIFIED'),
-- ('Helicopter', 'Air', 'NEED_VERIFICATION');
--
-- -- Insert into equip_weapon
-- INSERT INTO equip_weapon (equip_id, weapon_id) VALUES
-- (1, 1),
-- (2, 2);
--
-- -- Insert into missions_transport
-- INSERT INTO missions_transport (miss_id, trans_id) VALUES
-- (1, 1),
-- (2, 2);
--
-- -- Insert into inspection
-- INSERT INTO inspection (emp_id, trans_id, service_date) VALUES
-- (1, 1, '2023-01-05'),
-- (2, 2, '2023-02-15');
--
-- -- Insert into missions_emp
-- INSERT INTO missions_emp (miss_id, emp_id) VALUES
-- (1, 1),
-- (2, 2);

-- some example of bad population // Заполнение таблицы с ошибками; Плохая популяция данных (Эти операции завершатся неудачей из-за ограничений)
--
-- -- Попытка вставить в базу с недопустимым статусом
-- INSERT INTO base (location, status) VALUES ('Base Charlie', 'INVALID_STATUS'); -- Это завершится неудачей из-за ограничения ENUM
-- --
-- -- Попытка вставить в mre с недопустимым значением kkal
-- INSERT INTO mre (breakfast, lunch, dinner, food_additives, kkal, proteins, fats, carbohydrate) VALUES
-- ('Oatmeal', 'Chicken Stew', 'Beef Jerky', 'None', 2500, 60, 50, 300); -- Это завершится неудачей из-за ограничения CHECK на kkal
-- --
-- -- Попытка вставить в employee с недопустимой датой рождения (несовершеннолетний)
-- INSERT INTO employee (name, surname, date_of_birth, education, hiring_date, pos_id, is_married, base_id) VALUES
-- ('Alice', 'Johnson', '2010-01-01', 'High School', '2023-01-01', 1, TRUE, 1); -- Это завершится неудачей из-за ограничения CHECK по возрасту
-- --
-- -- Попытка вставить в medical_card с недопустимым типом крови
-- INSERT INTO medical_card (emp_id, height_cm, weight_kg, diseases, blood, gender) VALUES
-- (1, 180, 75, 'None', 'RED', 'M'); -- Это завершится неудачей из-за ограничения ENUM
--
-- -- Попытка вставить в mission с несуществующим camp_id
-- INSERT INTO mission (camp_id, start_date_and_time, end_date_and_time, legal_status, departure_location, arrival_location, enemies) VALUES
-- (999, '2023-01-10 08:00:00', '2023-01-15 18:00:00', TRUE, 'Base Alpha', 'Base Bravo', 'None'); -- Это завершится неудачей из-за ограничения внешнего ключа

-- Simple Queries and Aggregations
-- Count of Employees by Marital Status
SELECT is_married, COUNT(*) AS employee_count
FROM employee
GROUP BY is_married;

--Average Salary by Position
SELECT p.name AS position_name, AVG(p.salary_rub) AS average_salary
FROM position p
JOIN employee e ON p.pos_id = e.pos_id
GROUP BY p.name;

-- Total Earnings and Spending for Campaigns
SELECT name, SUM(earning) AS total_earning, SUM(spending) AS total_spending
FROM campaign
GROUP BY name
LIMIT 10;

-- List of Employees with Medical Information
SELECT e.name, e.surname, mc.height_cm, mc.weight_kg, mc.blood
FROM employee e
JOIN medical_card mc ON e.emp_id = mc.emp_id;

--Count of Missions by Execution Status
SELECT execution_status, COUNT(*) AS mission_count
FROM campaign
GROUP BY execution_status
LIMIT 10;

-- Общая сумма доходов и расходов по кампаниям с учетом нормы прибыли
-- Этот запрос рассчитывает общую сумму доходов, расходов и нормы прибыли для каждой кампании.
SELECT
    name AS campaign_name,
    earning,
    spending,
    (earning - spending) AS profit,
    (earning - spending) / NULLIF(earning, 0) * 100 AS profit_margin_percentage
FROM
    campaign
ORDER BY
    profit DESC
LIMIT 10;

-- Количество сотрудников по статусу базы
-- Этот запрос подсчитывает количество сотрудников на каждой базе, сгруппированных по статусу базы (ОТКРЫТА или ЗАКРЫТА).
SELECT
    b.status AS base_status,
    COUNT(e.emp_id) AS employee_count
FROM
    base b
LEFT JOIN
    employee e ON b.base_id = e.base_id
GROUP BY
    b.status
ORDER BY
    base_status;
