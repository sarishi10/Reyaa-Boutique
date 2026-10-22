-- Run as trusted project owner only, AFTER client email is confirmed.
-- Approved admin: nisha.nairofficial0728@gmail.com. Do not insert a password here.
DO $$
DECLARE target_id uuid;
BEGIN
 SELECT id INTO target_id FROM auth.users WHERE lower(email)=lower('nisha.nairofficial0728@gmail.com');
 IF target_id IS NULL THEN RAISE EXCEPTION 'Matching Auth user not found. Create and verify the client account first.'; END IF;
 UPDATE auth.users SET raw_app_meta_data=coalesce(raw_app_meta_data,'{}'::jsonb)||jsonb_build_object('store_role','admin','must_change_password',true) WHERE id=target_id;
END $$;
SELECT id,email,raw_app_meta_data->>'store_role' AS store_role FROM auth.users WHERE lower(email)=lower('nisha.nairofficial0728@gmail.com');
