-- CRLF line endings, a trailing comment and a last statement without a delimiter.
CREATE TABLE complex_crlf (
  id INT PRIMARY KEY,
  note VARCHAR(100) -- crlf; comment
);
INSERT INTO complex_crlf VALUES (1, 'line one;
line two'),   -- a string with a line break; inside
  (2, 'second');

CREATE PROCEDURE complex_crlf_proc()
BEGIN
  UPDATE complex_crlf SET note = CONCAT(note, '!');
END;
CALL complex_crlf_proc();
INSERT INTO complex_crlf VALUES (3, 'last statement without a semicolon')   -- trailing comment; no newline at EOF