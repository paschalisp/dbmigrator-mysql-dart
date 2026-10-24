-- Unicode edge cases: other scripts, emoji and look-alike punctuation in comments, literals and identifiers.
-- Greek comment: Καλημέρα κόσμε; αυτό δεν είναι τέλος εντολής 'με απόστροφο
# 中文注释；这里有半角分号; 还有 "引号" 和 `反引号 和 'it's
/* تعليق بالعربية؛ فاصلة منقوطة ; and a bidi override: ‮reversed text */
-- Emoji in a comment 😀🎉; 👨‍👩‍👧‍👦 and a flag 🇬🇷 and a 🚀 rocket -- with dashes
/* 日本語のコメント；セミコロン; */ # 한국어 주석; 세미콜론
/* Ωμέγα */ /* ; */

CREATE TABLE `complex_unicode` (
  `id` int NOT NULL,
  `lang` varchar(20) NOT NULL,
  `label` text,
  `όνομα` varchar(50) DEFAULT NULL, -- a Greek identifier; ταυτότητα
  `名前` varchar(50) DEFAULT NULL, -- a CJK identifier; 识别码
  `اسم` varchar(50) DEFAULT NULL, /* an Arabic identifier؛ معرّف */
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Non-ASCII table and column names, with a Cyrillic one for good measure
CREATE TABLE `complex_表_πίνακας_جدول_ключ` (`ключ` int, `κλειδί` int, `キー` int);
INSERT INTO `complex_表_πίνακας_جدول_ключ` (`ключ`, `κλειδί`, `キー`) VALUES (1, 2, 3); -- ένα, 二, ثلاثة

INSERT INTO complex_unicode (id, lang, label) VALUES
  (1, 'el', 'Καλημέρα κόσμε; Ελληνικά ''με απόστροφο'' -- όχι σχόλιο'),
  (2, 'el', 'Ποιο είναι το όνομά σου;'),            -- U+037E looks like a semicolon, but is a Greek question mark
  (3, 'zh', '你好，世界；这是中文; "引号" /* 不是注释 */'),
  (4, 'zh', '繁體中文：資料庫遷移 # 不是註解'),
  (5, 'ja', 'こんにちは世界；日本語 カタカナ 漢字 -- コメントではない'),
  (6, 'ko', '안녕하세요 세계; 한국어'),
  (7, 'ar', 'مرحبا بالعالم؛ نص عربي; مع "اقتباس" و ''اقتباس'' # ليس تعليقا'),
  (8, 'ar', 'مرحبا ‮abc 123​ mixed LTR/RTL ‎‏ end'),
  (9, 'he', 'שלום עולם; עברית /* לא הערה */'),
  (10, 'ru', 'Привет, мир; кириллица -- не комментарий'),
  (11, 'hi', 'नमस्ते दुनिया; देवनागरी'),
  (12, 'th', 'สวัสดีชาวโลก; ภาษาไทย'),
  (13, 'emoji', '😀😃😄 😍🥳; 🚀🔥 ''💯'' "🎉"'),
  (14, 'emoji', '👨‍👩‍👧‍👦 🇬🇷 👍🏽 ❤️ ✌️ 🏳️‍🌈'),                    -- ZWJ sequences, a flag, a skin tone and variation selectors
  (15, 'fullwidth', '；；；＇＂｀－－　＃'),                  -- fullwidth look-alikes and an ideographic space are not special
  (16, 'combining', 'é ñ ü ñ'),
  (17, 'separators', 'line separator and paragraph separator; NBSP here ﻿bom ​zwsp'),
  (18, 'mixed', 'Ελληνικά 中文 العربية 😀 English; all together -- # /* */'),
  (19, 'quotes', '‘curly’ “curly” «guillemets» „low“ ‹single› ′prime″ ´acute˜ ʼmodifier'),
  (20, 'escapes', 'backslash \\ then \Ω \😀 \中; and ''quoted'' 😀'),
  (21, 'el', 'Ένα'  'Δύο'  '😀'),                                   -- adjacent literals are concatenated
  (22, 'astral', '𝒜𝔅ℂ 𠜎𠜱𠝹 𐍈 𝄞;'),                                  -- characters outside the BMP
  (23, 'text', 'γλώσσα; 语言; لغة; 🌍'),                           -- text that would be a column comment elsewhere
  (24, 'text', 'πίνακας; 表; جدول; 📦');                           -- text that would be a table comment elsewhere

UPDATE complex_unicode SET `όνομα` = 'Νίκος', `اسم` = 'أحمد' WHERE id = 1; UPDATE complex_unicode SET `名前` = '名前；値' WHERE id = 3; -- δύο εντολές; 两条语句

UPDATE complex_unicode
   SET label = CONCAT(label, ' ✓') -- προσθήκη; 追加；إضافة
 WHERE id = 4 /* όπου; 条件；حيث */
   AND lang = 'zh' # 中文；
;

SET @unicode_var = 'Ωμέγα; 😀 中';
INSERT INTO complex_unicode (id, lang, label) VALUES (40, 'var', @unicode_var);

/*!40101 SET @unicode_cond = 'υπό όρους; 条件付き 😀' */;
INSERT INTO complex_unicode (id, lang, label) VALUES (41, 'cond', @unicode_cond);

INSERT INTO complex_unicode (id, lang, label) VALUES (42, 'concat', CONCAT('α', CHAR(59 USING utf8mb4), 'β', CHAR(0xF09F9880 USING utf8mb4)));

SELECT 'Ελληνικά;' AS `στήλη;`, "中文；", 'عربي؛';SELECT '😀';SELECT 'ä' ;

-- Routine bodies are stored as utf8mb3 by the servers, so this one stays inside the BMP
CREATE PROCEDURE complex_unicode_proc(IN p_lang VARCHAR(20))
BEGIN
    DECLARE greeting VARCHAR(100) DEFAULT 'Γειά σου; 你好; مرحبا; ★ // not the end';
    -- σχόλιο μέσα στη διαδικασία; 过程中的注释; تعليق داخل الإجراء ★
    INSERT INTO complex_unicode (id, lang, label) VALUES (900, p_lang, greeting); # 完了；
END;

CALL complex_unicode_proc('proc');
