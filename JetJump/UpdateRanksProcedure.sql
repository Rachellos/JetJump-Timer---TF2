DELIMITER //
DROP PROCEDURE IF EXISTS `UpdateMapPoints`//
CREATE PROCEDURE `UpdateMapPoints`(IN `in_map_id` INT, IN `in_run_type` INT, IN `in_run_id` INT, IN `in_class` INT) NOT DETERMINISTIC CONTAINS SQL SQL SECURITY INVOKER BEGIN 
                    DECLARE v_rec_id, v_player_id, completions, v_tier INT; 
                    DECLARE v_rank INT DEFAULT 0; 
                    DECLARE calculated_points, default_points, wr, pr DOUBLE; 
                    DECLARE done INT DEFAULT FALSE; 
                    DECLARE cur CURSOR FOR SELECT record_id, player_id, time FROM records WHERE map_id = in_map_id AND run_type = in_run_type AND run_id = in_run_id AND class = in_class ORDER BY time ASC; 
                    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE; 
                    OPEN cur; 
                    SELECT COUNT(*) INTO completions FROM records WHERE map_id = in_map_id AND run_type = in_run_type AND run_id = in_run_id AND class = in_class;
                    IF in_class = 0 
                    THEN 
                        SELECT soldier_tier INTO v_tier FROM map_info WHERE map_id = in_map_id AND run_type = in_run_type AND run_id = in_run_id; 
                    ELSEIF in_class = 1 
                    THEN 
                        SELECT demoman_tier INTO v_tier FROM map_info WHERE map_id = in_map_id AND run_type = in_run_type AND run_id = in_run_id; 
                    END IF; 
                    SELECT pts INTO default_points FROM points WHERE tier = v_tier; 
                    loop_through_rows:LOOP 
                        FETCH cur INTO v_rec_id, v_player_id, pr; 
                        IF done THEN 
                            LEAVE loop_through_rows; 
                        END IF; 
                        SET v_rank = v_rank + 1; 
                        IF v_rank = 1 
                        THEN 
                            SET wr = pr; 
                            SET calculated_points = default_points + ((default_points * ((wr / pr) * 1.5)) * 1.3) + completions; 
                        ELSE 
                            SET calculated_points = default_points + ((default_points * ((wr / pr) * 1.5)) / 1.3) + completions * 0.75;
                        END IF;
                        SET calculated_points = calculated_points / (in_run_type + 1);
                        UPDATE records SET `records`.`rank` = (SELECT v_rank), `records`.`points` = (SELECT calculated_points) WHERE record_id = v_rec_id;
                        IF in_class = 0
                        THEN
                        	UPDATE players SET soldier_points = (SELECT SUM(points) FROM records WHERE player_id = v_player_id AND class = in_class) WHERE id = v_player_id;
                        ELSEIF in_class = 1
                        THEN
                        	UPDATE players SET demoman_points = (SELECT SUM(points) FROM records WHERE player_id = v_player_id AND class = in_class) WHERE id = v_player_id;
                        END IF;
                    END LOOP; 
                    CLOSE cur;
                    SET @rank = 0;
                    IF in_class = 0
                    THEN
                        UPDATE players
                            SET soldier_rank = (@rank := @rank + 1)
                        WHERE soldier_points > 0.0
                        ORDER BY soldier_points DESC;
                    ELSEIF in_class = 1
                    THEN
                    	UPDATE players
                            SET demoman_rank = (@rank := @rank + 1)
                        WHERE demoman_points > 0.0
                        ORDER BY demoman_points DESC;
                    END IF;
                END//
DELIMITER ;