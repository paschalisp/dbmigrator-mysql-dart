-- Routines with nested blocks and tricky literals inside the bodies.

CREATE TABLE complex_edge_log (
    id INT AUTO_INCREMENT PRIMARY KEY,
    message TEXT NOT NULL
) DEFAULT CHARSET=utf8mb4;

-- A "//" inside strings and comments of the body is just text
CREATE FUNCTION complex_fib(n INT) RETURNS BIGINT
    DETERMINISTIC
BEGIN
    DECLARE a BIGINT DEFAULT 0;
    DECLARE b BIGINT DEFAULT 1;
    DECLARE t BIGINT;
    DECLARE i INT DEFAULT 0;
    -- iterative; no recursion // here
    WHILE i < n DO
        SET t = a + b;
        SET a = b;
        SET b = t;
        SET i = i + 1;
    END WHILE;
    RETURN a;
END;

CREATE PROCEDURE complex_classify(IN n INT, OUT kind VARCHAR(50))
BEGIN
    DECLARE note VARCHAR(100) DEFAULT 'uses // inside; a string';
    outer_block: BEGIN
        IF n < 0 THEN
            SET kind = 'negative';
            LEAVE outer_block;
        ELSEIF n = 0 THEN
            SET kind = 'zero';
            LEAVE outer_block;
        END IF;
        CASE
            WHEN n < 10 THEN SET kind = 'small';
            WHEN n < 100 THEN SET kind = 'medium';
            ELSE SET kind = 'large';
        END CASE;
    END outer_block;
    /* log; the classification // with slashes */
    INSERT INTO complex_edge_log (message) VALUES (CONCAT(note, ' => ', kind)); # done; really
END;

-- mysqldump style trigger: versioned comments wrapping the whole definition
/*!50003 CREATE*/ /*!50017 DEFINER=`root`@`%`*/ /*!50003 TRIGGER `complex_edge_before_insert` BEFORE INSERT ON `complex_edge` FOR EACH ROW BEGIN
  IF NEW.label IS NULL THEN
    SET NEW.label = 'defaulted; by trigger';
  END IF;
END */;

-- A "$$" inside a string of the body is just text
CREATE PROCEDURE complex_note(IN p_text TEXT)
BEGIN
    INSERT INTO complex_edge_log (message) VALUES (CONCAT('note: ', p_text, ' $ $$ is not the end inside a string'));
END;

SET @edge_sql = 'INSERT INTO complex_edge (id, label, amount) VALUES (101, ''prepared; statement'', 1)';
PREPARE edge_stmt FROM @edge_sql;
EXECUTE edge_stmt;
DEALLOCATE PREPARE edge_stmt;

INSERT INTO complex_edge (id, label, amount) VALUES (100, NULL, 1);

CALL complex_classify(5, @kind);
INSERT INTO complex_edge (id, label, amount) VALUES (102, @kind, complex_fib(10));
CALL complex_classify(-3, @kind);
INSERT INTO complex_edge (id, label, amount) VALUES (103, @kind, complex_fib(20));
CALL complex_note('semi; colon -- and # and /* */');
