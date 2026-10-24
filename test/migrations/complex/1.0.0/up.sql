-- MySQL dump style script
-- Host: localhost    Database: test_db
-- ------------------------------------------------------
-- Server version	8.0; with a semicolon in a comment

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!50503 SET NAMES utf8mb4 */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;

--
-- Table structure for table `complex_items`
--

DROP TABLE IF EXISTS `complex_items`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `complex_items` (
  `id` int NOT NULL AUTO_INCREMENT, -- the id; unique
  `label` varchar(255) NOT NULL COMMENT 'it''s a label; really', /* inline; comment */
  `note` text, # hash comment; with a semicolon
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `complex_items`
--

INSERT INTO `complex_items` (`label`, `note`) VALUES
  ('semicolon;inside', 'first'),
  ('-- not a comment', 'second'),
  ('/* not a comment */', 'third'),
  ('# not a comment', 'fourth'),
  ('it''s quoted', 'fifth'),
  ("double ""quoted""; value", 'sixth'),
  ('backslash \\ and \' escape; ok', 'seventh'),
  ('multi
line; value', NULL);

/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;

-- Dump completed; trailing comment without a statement
