DELIMITER //
create trigger wl_cancel_on_new_ses after insert on sessions
for each row
begin
	set @username = (select username from users where id = new.user_id);
	if @username is not null then
		update waiting set canceled=now(),canceled_by='new_ses_trigger' where username=@username and filled is null and canceled is null;
	end if;
end//
DELIMITER ;
