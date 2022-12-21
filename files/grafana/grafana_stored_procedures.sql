-- Remove unique constraint on email column from user table as we could have different users sharing the same email address
SET @exists = (SELECT COUNT(*) FROM information_schema.statistics WHERE `table_name` = 'user' AND `index_name` = 'UQE_user_email' AND `table_schema` = 'grafana');
SET @sqlstmt := IF( @exists > 0, 'ALTER TABLE `grafana`.`user` DROP INDEX `UQE_user_email`', 'SELECT ''UQE_user_email exists''');
PREPARE stmt FROM @sqlstmt;
EXECUTE stmt;

-- 
-- stored procedures called by rgmweb triggers
-- 
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
	IN rgmuserid INT, 
	IN rgmgroupid INT
)
	COMMENT 'create Grafana user from rgmweb INSERT trigger'
BEGIN
	DECLARE is_grpadmin BOOL;
	DECLARE userid MEDIUMINT;
	DECLARE createddate DATETIME;
	DECLARE defrole varchar(20);

	SET is_grpadmin = FALSE;
	SET defrole = 'Viewer';

	IF rgmgroupid = 1 THEN
		SET is_grpadmin = TRUE;
		SET defrole = 'Editor';
	END IF;

	IF rgmuserid = 1 THEN
		SET is_grpadmin = TRUE;
		SET defrole = 'Admin';
	END IF;

	INSERT INTO `grafana`.`user` SET
		`login` = username,
		`version` = 0,
		`email` = useremail,
		`name` = fullname,
		`org_id` = 1,
		`is_admin` = is_grpadmin,
		`email_verified` = TRUE,
		`created` = NOW(),
        `updated` = NOW();
	SET @userid = (SELECT LAST_INSERT_ID());
	SET @createddate = (SELECT created FROM `grafana`.`user` WHERE `id` = @userid);
	IF @userid IS NOT NULL THEN
		INSERT INTO `grafana`.`org_user` SET
			`org_id` = 1,
			`user_id` = @userid,
			`role` = defrole,
			`created` = @createddate,
			`updated` = NOW();
	END IF;

	-- adds default dashboard
	-- Can't presume the default dashboard from its name, so limit to the first row for default value
	SET @dashid = (SELECT id FROM grafana.dashboard WHERE title = 'Multi-System metrics' LIMIT 1);
	IF (SELECT COUNT(`id`) FROM `grafana`.`star` WHERE `user_id` = @userid AND `dashboard_id` = @dashid) = 0 THEN
		INSERT INTO  `grafana`.`star` SET `user_id` = @userid, `dashboard_id` = @dashid;
	END IF;
	IF (SELECT COUNT(*) FROM `grafana`.`preferences` WHERE `user_id` =  @userid AND `org_id` = 1) = 0 THEN
		INSERT INTO `grafana`.`preferences` SET
			`org_id` = 1,
			`user_id` = @userid,
			`version` = 0,
			`home_dashboard_id` = @dashid,
			`timezone` = '',
			`theme` = '',
			`created` = NOW(),
			`updated` = NOW(),
			`team_id` = 0;
	ELSE
		UPDATE `grafana`.`preferences` SET `home_dashboard_id` = @dashid WHERE  @userid AND `org_id` = 1;
	END IF;
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
	IN rgmuserid INT, 
	IN rgmgroupid INT
)
	COMMENT 'update Grafana user from rgmweb UPDATE trigger'
BEGIN
	DECLARE is_grpadmin BOOL;
	DECLARE userid MEDIUMINT;
	DECLARE defrole varchar(20);

	SET is_grpadmin = FALSE;
	SET defrole = 'Viewer';

	IF rgmgroupid = 1 THEN
		SET is_grpadmin = TRUE;
		SET defrole = 'Editor';
	END IF;

	IF rgmuserid = 1 THEN
		SET is_grpadmin = TRUE;
		SET defrole = 'Admin';
	END IF;

	SET @userid = (SELECT `id` FROM `grafana`.`user` WHERE `login` = username);
	UPDATE `grafana`.`user` SET
		`email` = useremail,
		`name` = fullname,
		`org_id` = 1,
		`is_admin` = is_grpadmin,
		`email_verified` = TRUE,
		`updated` = NOW()
	WHERE `id` = @userid;

	IF (SELECT COUNT(*) FROM `grafana`.`org_user` WHERE `user_id` = @userid AND `role` = defrole) = 0 THEN
		UPDATE `grafana`.`org_user` SET
			`role` = defrole,
			`updated` = NOW()
		WHERE `user_id` = @userid;
	END IF;
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
	DECLARE orgid MEDIUMINT;

	SET @userid = (SELECT `id` FROM `grafana`.`user` WHERE login = username);
	IF @userid IS NOT NULL THEN
		SET @orgid = (SELECT `id` FROM `grafana`.`org_user` WHERE `user_id` = @userid);
		SET SQL_SAFE_UPDATES=0;
		IF @orgid IS NOT NULL THEN
			DELETE FROM `grafana`.`org_user` WHERE `id` = @orgid;
		END IF;
		DELETE FROM `grafana`.`user` WHERE `id` = @userid;
		DELETE FROM `grafana`.`star` WHERE `user_id` = @userid;
		DELETE FROM `grafana`.`preferences` WHERE `user_id` = @userid;
		SET SQL_SAFE_UPDATES=1;
	END IF;
END;
$$
