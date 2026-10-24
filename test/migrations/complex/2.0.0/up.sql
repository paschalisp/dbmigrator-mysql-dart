-- Stored routines and triggers whose bodies contain semicolons, sent to the server together with other statements.

CREATE TABLE complex_log (
    id INT AUTO_INCREMENT PRIMARY KEY,
    message VARCHAR(255) NOT NULL
);

CREATE PROCEDURE complex_add_item(IN p_label VARCHAR(255))
BEGIN
    -- a comment; with a semicolon inside the body
    INSERT INTO complex_items (label, note) VALUES (p_label, 'added; by procedure');
    INSERT INTO complex_log (message) VALUES (CONCAT('added: ', p_label)); # another; comment
END;

CREATE FUNCTION complex_count_items() RETURNS INT
    READS SQL DATA
BEGIN
    DECLARE total INT;
    SELECT COUNT(*) INTO total FROM complex_items;
    RETURN total;
END;

CREATE TRIGGER complex_items_after_delete AFTER DELETE ON complex_items
FOR EACH ROW
BEGIN
    INSERT INTO complex_log (message) VALUES (CONCAT('deleted: ', OLD.label));
END;

CALL complex_add_item('from migration; with "quotes" and -- dashes');

DELETE FROM complex_items WHERE note = 'first';
