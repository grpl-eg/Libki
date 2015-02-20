DELIMITER //
create trigger next_res before delete on sessions
for each row
begin
	set @loc = (select location from clients where id = old.client_id);
	set @wid = (select id from waiting where canceled is null and filled is null and location = @loc order by created limit 1);
	set @res_username = (select username from waiting where id = @wid);
	if @res_username is not null then
		set @res_uid = (select id from users where username=@res_username);
		insert into reservations (client_id,user_id) values(old.client_id,@res_uid);
		update waiting set filled=now() where id = @wid;
	end if;
end//
DELIMITER ;
