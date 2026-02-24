ALTER TABLE table1
    ADD COLUMN col3 TEXT;

ALTER TABLE table2
    ADD COLUMN col3 TEXT;

-- Add another table
CREATE TABLE table3 (
    id INT PRIMARY KEY,
    col1 TEXT,
    col2 TEXT,
    col3 TEXT
);