-- Edge cases for multi-statement scripts: literals, escapes, comments, identifiers and odd whitespace.
-- A semicolon inside a line comment must be ignored;
# ...and so must one inside a hash comment;
/*
a block comment can span lines; and even contain a semicolon at the start of a line
;
*/
/**/ /***/ /* * / ; */ --	a dash comment followed by a tab; not a statement end
--
-- (the line above is an empty dash comment)

-- comments in front of a statement, containing semicolons
/* only a comment; */ # only a hash comment;

CREATE TABLE `complex_edge` (
  `id` int NOT NULL AUTO_INCREMENT,
  `label` text,
  `amount` int DEFAULT NULL,
  delimiter varchar(20) DEFAULT NULL, -- a column named like a client command; it is a plain column
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='table; with -- and # and /* in its comment';

-- Comments with unbalanced quotes must not start a string: it's a comment; "also double and a ` backtick
# it's a hash comment; "with" an unbalanced ' quote
/* don't; "break` the parser */
INSERT INTO complex_edge (id, label, amount) VALUES
  (1, '', 1),                                              -- empty string; nothing in it
  (2, ';', 2),                                             -- just the delimiter
  (3, ';;', 3),
  (4, '''', 4),                                            -- a single quote, escaped by doubling
  (5, '''''', 5),                                          -- two single quotes
  (6, '\'', 6),                                            -- a single quote, escaped with a backslash
  (7, '"', 7),                                             # a double quote inside single quotes
  (8, "'", 8),                                             /* a single quote inside double quotes; */
  (9, "\"", 9),
  (10, 'a\\', 10),                                         -- ends with an escaped backslash right before the quote;
  (11, 'C:\\temp\\; D:\\', 11),
  (12, 'a\;b', 12),                                        -- unknown escape sequence
  (13, '100\%', 13),
  (14, 'tab\there\nnewline', 14),
  (15, "a ""b""; c", 15),
  (16, 'ab;' 'cd', 16),                                    -- adjacent literals are concatenated
  (17, CONCAT('a', CHAR(59 USING utf8mb4), 'b'), 17),
  (18, 'ünï;cödé ✓ – ‘quoted’', 18),
  (19, '-- ;', 19),
  (20, 'first line
;
last line;', 20),
  (21, '*/ ; /*', 21),
  (22, '#--/*;*/', 22),
  (23, '$$ // ;; ||', 23),
  (24, '`;`', 24),
  (25, 'minus minus', 10--4),                                -- "--" without whitespace is arithmetic, not a comment
  (26, 'minus comment minus', 10-/* ; */-4),
  (27, 'comment between operands', 10 /* ; */ + -- add; one
   1);

UPDATE complex_edge SET label = '/* x */' WHERE id = 1; UPDATE complex_edge SET amount = amount + 100 WHERE id = 2; -- two statements; one line

UPDATE complex_edge
   SET amount = 1000 -- bump; the amount
 WHERE id = 3 /* where; clause */
   AND label = ';;' # hash; comment
;

UPDATE complex_edge SET label='x;y'WHERE id=5;

SET @edge_var = 'value; with semicolon';
INSERT INTO complex_edge (id, label, amount) VALUES (40, @edge_var, 40);

/*!40101 SET @edge_cond = 'conditional; comment' */;
INSERT INTO complex_edge (id, label, amount) VALUES (41, @edge_cond, 41);

SELECT 'a;b' AS `col;name`, "c;d", 1;SELECT 2;SELECT 3 ;
SELECT /* ; */ 4 # ;
;

-- Quoted identifiers containing semicolons, quotes and comment markers
CREATE TABLE `complex;odd``name` (`col;umn` INT, `a``b` INT, `dash -- col` INT, `hash # col` INT, `/* c */` INT);
INSERT INTO `complex;odd``name` (`col;umn`, `a``b`, `dash -- col`, `hash # col`, `/* c */`) VALUES (1, 2, 3, 4, 5);
