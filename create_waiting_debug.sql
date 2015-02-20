CREATE TABLE `_debug` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `msg` text,
  `d_time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=17 DEFAULT CHARSET=latin1

CREATE TABLE `waiting` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `username` varchar(30) DEFAULT NULL,
  `location` varchar(30) DEFAULT NULL,
  `created` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `canceled` timestamp NULL DEFAULT NULL,
  `canceled_by` varchar(30) DEFAULT NULL,
  `filled` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=35 DEFAULT CHARSET=latin1

