CREATE TABLE `output` (
  `id` int(10) NOT NULL AUTO_INCREMENT,
  `d` int(10) DEFAULT NULL,
  `h` int(10) DEFAULT NULL,
  `m` int(10) DEFAULT NULL,
  `s` int(10) DEFAULT NULL,
  `queue` varchar(15) DEFAULT NULL,
  `_max` int(10) DEFAULT NULL,
  `_free` int(10) DEFAULT NULL,
  `_min` int(10) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `Index 2` (`d`),
  KEY `Index 3` (`h`,`m`,`s`),
  KEY `Index 4` (`queue`)
) ENGINE=InnoDB AUTO_INCREMENT=310247 DEFAULT CHARSET=utf8