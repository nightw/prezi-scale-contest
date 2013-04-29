CREATE TABLE `requests` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `d` date NOT NULL,
  `h` int(10) unsigned NOT NULL,
  `m` int(10) unsigned NOT NULL,
  `s` int(10) unsigned NOT NULL,
  `queue` varchar(10) NOT NULL,
  `runtime` double NOT NULL,
  PRIMARY KEY (`id`),
  KEY `h` (`h`,`m`,`s`),
  KEY `queue` (`queue`),
  KEY `date` (`d`) USING BTREE
) ENGINE=InnoDB AUTO_INCREMENT=0 DEFAULT CHARSET=utf8;