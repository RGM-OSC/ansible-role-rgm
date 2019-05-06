USE grafana;

DELIMITER $$

--
-- Grafana INSERT procedure ---------------------------------------------------
--
DROP PROCEDURE IF EXISTS `insert_grafana_user_from_rgmweb` $$
CREATE DEFINER=`rgminternal`@`localhost` PROCEDURE `insert_grafana_user_from_rgmweb`(
    IN username VARCHAR(64),
    IN fullname VARCHAR(64),
    IN useremail VARCHAR(64),
    IN groupid INT
)
COMMENT 'create Grafana user from rgmweb INSERT trigger'
BEGIN
	DECLARE is_grpadmin BOOL;
	DECLARE userid MEDIUMINT;
	DECLARE createddate DATETIME;
	DECLARE defrole varchar(20);

	SET is_grpadmin = FALSE;
	SET defrole = 'View';

	IF groupid = 1 THEN
		SET is_grpadmin = TRUE;
		SET defrole = 'Editor';
	END IF;

	INSERT INTO `grafana`.`user` SET
		login = username,
		email = useremail,
		name = fullname,
		org_id = 1,
		is_admin = is_grpadmin,
		email_verified = TRUE,
		created = NOW();

	SET userid = (SELECT id FROM `grafana`.`user` WHERE login = username);
	SET createddate = (SELECT created FROM `grafana`.`user` WHERE login = username);
	INSERT INTO grafana.org_user SET
		org_id = 1,
		user_id = userid,
		role = defrole,
		created = createddate,
		updated = NOW();
END;
$$

--
-- Grafana UPDATE procedure ---------------------------------------------------
--
DROP PROCEDURE IF EXISTS `update_grafana_user_from_rgmweb` $$
CREATE DEFINER=`rgminternal`@`localhost` PROCEDURE `update_grafana_user_from_rgmweb`(
    IN username VARCHAR(64),
    IN fullname VARCHAR(64),
    IN useremail VARCHAR(64),
    IN userid INT, 
    IN groupid INT
)
COMMENT 'update Grafana user from rgmweb UPDATE trigger'
BEGIN
	DECLARE is_grpadmin BOOL;
	DECLARE grafanauserid MEDIUMINT;
	DECLARE defrole varchar(20);

	SET is_grpadmin = FALSE;
	SET defrole = 'View';

	IF groupid = 1 THEN
		SET is_grpadmin = TRUE;
		SET defrole = 'Editor';
	END IF;

	IF userid = 1 THEN
		SET is_grpadmin = TRUE;
		SET defrole = 'Admin';
	END IF;

	UPDATE `grafana`.`user` SET
		email = useremail,
		name = fullname,
		org_id = 1,
		is_admin = is_grpadmin,
		email_verified = TRUE,
		updated = NOW()
		WHERE login = username;

	SET grafanauserid = (SELECT id FROM `grafana`.`user` WHERE login = username);

	UPDATE `grafana`.`org_user` SET
		role = defrole,
		updated = NOW()
	WHERE user_id = grafanauserid;
END;
$$

--
-- Grafana DELETE procedure ---------------------------------------------------
--
DROP PROCEDURE IF EXISTS `delete_grafana_user_from_rgmweb` $$
CREATE DEFINER=`rgminternal`@`localhost` PROCEDURE `delete_grafana_user_from_rgmweb`(
    IN username VARCHAR(64)
)
COMMENT 'delete Grafana user from rgmweb DELETE trigger'
BEGIN
	DECLARE userid MEDIUMINT;

	SET userid = (SELECT id FROM `grafana`.`user` WHERE login = username);
	DELETE FROM `grafana`.`user` WHERE login = username;
	DELETE FROM `grafana`.`org_user` WHERE user_id = userid;
END;
$$
