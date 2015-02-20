DELIMITER //
DROP FUNCTION IF EXISTS expired_res; //

create function expired_res(rid int , cid int) returns text
begin
  declare loc text;
  declare cname text;
  declare wid int;
  declare res_username text default NULL;
  declare res_uid int;
  declare rmsg text default 'none';
  declare dmsg text;

	delete from reservations where id = rid;
	select concat('deleted res ', rid, ' for client ', cid) into dmsg;
	CALL Debug(dmsg);
	select location, name into loc, cname from clients where id = cid;
	select id, username into wid, res_username from waiting where canceled is null and filled is null and location = loc order by created limit 1;

	if res_username is not null then
		select id into res_uid from users where username = res_username;
		insert into reservations (client_id,user_id) values(cid,res_uid);
		update waiting set filled=now() where id = wid;
		select concat('refilled client ', cid, ' reservation for ', res_username) into dmsg;
		CALL Debug(dmsg);
		select concat(cname, ' ', res_username) into rmsg;
	end if;
return rmsg;
end//
DELIMITER ;
