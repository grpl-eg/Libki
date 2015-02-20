create view oldest_active as select c.name,s.status,u.minutes,max(st.`when`) AS login_time,timediff(now(),max(st.`when`)) AS length,u.username,u.notes,c.id AS cid,u.id AS uid
       from clients c join sessions s on c.id = s.client_id
	 join users u on u.id = s.user_id
         join statistics st on st.client_name = c.name
  where st.action = 'LOGIN' group by c.name order by u.minutes,timediff(now(),max(st.`when`)) desc
