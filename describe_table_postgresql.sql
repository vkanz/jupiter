USE [ShturmanDiagnostics]
GO
/****** Object:  StoredProcedure [dbo].[describe_table_postgresql]    Script Date: 16.08.2019 11:45:48 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		<Author,,Name>
-- Create date: <Create Date,,>
-- Description:	<Description,,>
-- =============================================
ALTER procedure [dbo].[describe_table_postgresql]
	@table_name nvarchar(128) = null, /*имя таблицы*/
	@database_name nvarchar(128) = null,/*запрос к другой БД не реализован*/ 
	@schema_name nvarchar(128) = null,/*имя исходной схемы, если не задано, то подразумевается "dbo"*/
  @target_schema_name nvarchar(128) = null/*имя целевой схемы, если не задано, то совпадает с исходной*/ 

/* если данная процедура используется в качестве скрипта, то вместо функции dbo.camel_to_underlined()
   следует использовать следующую временную процедуру:
if object_id('TempDB..#camel_to_underlined') is not null drop procedure #camel_to_underlined
go
create procedure #camel_to_underlined(
  @src varchar(128),
  @dst varchar(128) out
  )
as
begin
  declare 
    @len int = len(@src),
    @i int = 1,
    @curr varchar(1),
    @prev varchar(1);

  set @dst = '';
  while @i <= @len 
  begin
    set @curr = substring(@src, @i, 1);    
    if ascii(@curr) between 65/*ascii('A')*/ and 90/*ascii('Z')*/
      and ascii(@prev) between 97/*ascii('a')*/ and 122/*ascii('z')*/
      set @dst = @dst + '_';
    set @dst = @dst + @curr;
    set @i = @i + 1;
    set @prev = @curr;
  end;
  set @dst = lower(@dst);
end;
*/
as
begin
	set nocount on;

	declare	@type_tbl table (
				ms_type nvarchar(30),
				fb_type nvarchar(128),
				lenth_sign int
				);

--Type matching, see: https://severalnines.com/blog/migrating-mssql-postgresql-what-you-should-know
	insert into @type_tbl values 
		('bit', 'boolean', 0),
    ('datetime', 'timestamp', 0),
		('datetime2', 'timestamp', 0),
		('int', 'integer', 0),
		('nvarchar', 'varchar(%s)', 1),
		('numeric', 'numeric(%s, %s)', 0),
		('uniqueidentifier', 'uuid', 0);

	declare @ordinal_position int,
			@column_name nvarchar(128),
      @tmp nvarchar(128),
      @tmp2  nvarchar(128),
			@data_type nvarchar(128),
			@character_maximum_length int,
			@datetime_precision int,
			@is_nullable varchar(3), 
			@column_default varchar(128),
      @full_table_name varchar(256),
			@db_name varchar(128),
			@sch_name varchar(128),
      @tgt_sch_name varchar(128);


	if @table_name is null 
		throw 50001, 'Parameter "@table_name" must be defined', 0

  if lower(coalesce(@database_name, db_name())) <> lower(db_name())
		throw 50002, 'Access to other database is not implemented', 0

--Default Database & Schema
	if @database_name is null 
		select @db_name = lower(db_name())
	else
		set @db_name = lower(@database_name);

	if @schema_name is null 
		select @sch_name = 'dbo'
	else
		set @sch_name = lower(@schema_name);
  if @target_schema_name is null
    if @sch_name = 'dbo'
      set @tgt_sch_name = 'public' 
    else 
      set @tgt_sch_name = @sch_name
  else
    set @tgt_sch_name = @target_schema_name;
  set @full_table_name = @tgt_sch_name + '.' + dbo.camel_to_underlined(@table_name);

--Cursor
	declare cur cursor fast_forward for
		select ordinal_position, column_name, data_type, character_maximum_length,
			datetime_precision, is_nullable, column_default
		from INFORMATION_SCHEMA.COLUMNS/*запрос к БД "otherdb": ...from othersdb.INFORMATION_SCHEMA...*/ 
		where lower(table_name) = lower(@table_name)
		and lower(table_catalog) = @db_name /*вообще-то, лишнее: запрос показывает только текущую БД--*/
		and lower(table_schema) = @sch_name 
		order by ordinal_position;
	open cur;

	fetch next from cur into @ordinal_position, @column_name, @data_type, 
		@character_maximum_length, @datetime_precision, @is_nullable, @column_default;

--No data found
	if @@fetch_status <> 0 
	begin
		if @@fetch_status = -2
			throw 50001, 'The record does not exist or deleted.', 0
		else
		begin
			declare @msg varchar(128);
			set @msg = 'fetch_status=' + cast(@@fetch_status as varchar) + ' for table "' + 
        @db_name + '.' + @sch_name + '.' + @table_name + '"';
			throw 50001, @msg, 0
		end
	end;

	declare
	  @def nvarchar(max),
	  @part nvarchar(256),
	  @fb_type nvarchar(128),
	  @lenth_sign int,
	  @length_str nvarchar(10);

--"create table..."  
	exec master..xp_sprintf @part output, 'create table %s (', @full_table_name;
	set @def = @part;

--Fields Loop
	while @@fetch_status = 0
	begin
		if @ordinal_position > 1 
			set @def = @def + ',';
		set @def = @def + char(13) + char(9);

		set @fb_type = null;
			
		select @fb_type = fb_type, @lenth_sign = lenth_sign 
		from @type_tbl where ms_type = @data_type;

		if @fb_type is null 
			set @fb_type = @data_type
		else
		begin
			if @lenth_sign = 1  
			begin
				set @length_str = cast(@character_maximum_length as varchar);
				exec master..xp_sprintf @fb_type output, @fb_type, @length_str
			end;
		end;

	--type
    set @tmp = dbo.camel_to_underlined(@column_name);
		exec master..xp_sprintf @part output, '%s %s', @tmp, @fb_type
	--default
		if @column_default is not null
			set @part = @part + ' default ' + @column_default;
	--nullable
		if @is_nullable = 'NO' 
			set @part = @part + ' not null'
		set @def = @def + @part;

		fetch next from cur into @ordinal_position, @column_name, @data_type, 
			@character_maximum_length, @datetime_precision, @is_nullable, @column_default;
	end;
	set @def = @def + char(13) + ');' + char(13);

	close cur;
	deallocate cur;

--Primary key
	declare @constraint_name varchar(128) = null,
			@column_list varchar(128) = '';
	set @column_name = null;

	declare cur cursor fast_forward for
		select t.constraint_name, c.column_name  
		from INFORMATION_SCHEMA.TABLE_CONSTRAINTS t, 
			INFORMATION_SCHEMA.CONSTRAINT_COLUMN_USAGE c,
			INFORMATION_SCHEMA.KEY_COLUMN_USAGE u 
		where 1=1
		and c.constraint_name = t.constraint_name
		and c.table_name = t.table_name
		and c.table_schema = t.table_schema
		and c.table_catalog = t.table_catalog
		and u.constraint_name = t.constraint_name
		and u.table_name = t.table_name
		and u.table_schema = t.table_schema
		and u.table_catalog = t.table_catalog
		and u.column_name = c.column_name
		and t.constraint_type = 'primary key'
		and c.table_Name = lower(@table_name)
		and lower(t.table_catalog) = @db_name
		and lower(t.table_schema) = @sch_name
		order by u.ordinal_position;
	open cur;

	fetch next from cur into @constraint_name, @column_name;

	while @@fetch_status = 0
	begin
		if @column_list <> ''
		  set @column_list = @column_list + ', ';
		set @column_list = @column_list + dbo.camel_to_underlined(@column_name);

		fetch next from cur into @constraint_name, @column_name;
	end;

	close cur;
	deallocate cur;

	if @constraint_name is not null
	begin
    set @tmp = dbo.camel_to_underlined(@constraint_name);
		exec master..xp_sprintf @part output, 
			'alter table %s add constraint %s primary key (%s);', 
			@full_table_name, @tmp, @column_list
		set @def = @def + @part;
	end;

--Foreign keys
	declare	
		@pk_column_name varchar(128), 
		@pk_column_list varchar(128), 
		@fk_column_name varchar(128),
		@fk_column_list varchar(128),
		@pk_table_schema varchar(128),
		@pk_table_name varchar(128),
		@update_rule varchar(30) = '', 
		@delete_rule varchar(30) = '';

	declare cur cursor fast_forward for
		select tc.constraint_name 
		from INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
		where lower(tc.table_name) = lower(@table_name) 
		and lower(tc.table_catalog) = @db_name
		and lower(tc.table_schema) = @sch_name
		and tc.constraint_type = 'foreign key';

	set @part = '';

	open cur;
	fetch next from cur into @constraint_name;

	while @@fetch_status = 0
	begin
		set @fk_column_list = '';
		set @pk_column_name = '';

--Сomposite FK
		declare cur_fk cursor fast_forward for
			select cu.ordinal_position, cu.column_name, uk.column_name pk_column_name, uk.table_schema, uk.table_name,
				rc.update_rule, rc.delete_rule
			from INFORMATION_SCHEMA.REFERENTIAL_CONSTRAINTS rc,
				INFORMATION_SCHEMA.KEY_COLUMN_USAGE cu,
				(select tc.constraint_name, tc.constraint_catalog, tc.constraint_schema, cu2.ordinal_position,
					cu2.column_name, tc.table_schema, tc.table_name 
				from INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc,
					INFORMATION_SCHEMA.KEY_COLUMN_USAGE cu2 
				where tc.constraint_type = 'primary key'
				and cu2.constraint_name=tc.constraint_name
				) uk
			where rc.constraint_name = @constraint_name
			and lower(rc.constraint_catalog) = @db_name 
			and lower(rc.constraint_schema) = @sch_name
			and cu.constraint_name = rc.constraint_name
			and cu.constraint_catalog = rc.constraint_catalog
			and cu.constraint_schema = rc.constraint_schema
			and rc.unique_constraint_catalog = uk.constraint_catalog
			and rc.unique_constraint_name = uk.constraint_name
			and rc.unique_constraint_schema = uk.constraint_schema
			and cu.ordinal_position = uk.ordinal_position
			order by cu.ordinal_position;
--
		set @fk_column_list = '';
		set @pk_column_list = '';

		open cur_fk;
		fetch next from cur_fk into @ordinal_position, @fk_column_name, @pk_column_name, @pk_table_schema, @pk_table_name,
			@update_rule, @delete_rule;
		while @@fetch_status = 0
		begin
			if @fk_column_list <> ''
				set @fk_column_list = @fk_column_list + ', ';			
			set @fk_column_list = @fk_column_list +  dbo.camel_to_underlined(@fk_column_name);

			if @pk_column_list <> ''
				set @pk_column_list = @pk_column_list + ', ';
			set @pk_column_list = @pk_column_list + dbo.camel_to_underlined(@pk_column_name);

			fetch next from cur_fk into @ordinal_position, @fk_column_name, @pk_column_name, @pk_table_schema, @pk_table_name,
				@update_rule, @delete_rule;
		end;

		close cur_fk;
		deallocate cur_fk;

		if @fk_column_list <> ''
		begin
			if lower(@delete_rule) = 'no action'
				set @delete_rule = null
			else
				set @delete_rule = ' on delete ' + @delete_rule;

			if lower(@update_rule) = 'no action'
				set @update_rule = null
			else
				set @update_rule = ' on update ' + @update_rule;

      set @tmp = dbo.camel_to_underlined(@pk_table_name);
      set @tmp2 = dbo.camel_to_underlined(@constraint_name);
			exec master..xp_sprintf @part output, 
				'alter table %s add constraint %s foreign key (%s) references %s.%s (%s)', 
				@full_table_name, @tmp2, @fk_column_list, @pk_table_schema, @tmp, @pk_column_list; 
					
      set @tmp = @delete_rule;
      if @update_rule is not null
        set @tmp = @tmp + ' ';
      set @tmp = coalesce(@tmp, '') + coalesce(@update_rule, '');
      if @tmp <> ''
        set @part = @part + ' ';
      set @part = @part + @tmp + ';'

      if @delete_rule is not null
        set @tmp = @delete_rule

		end;

		set @def = @def + char(13) + @part;

		fetch next from cur into  @constraint_name;
	end;
	
	close cur;
	deallocate cur;

--Comments on Table
	set @part = null;
	select @part = cast(Value as varchar(256)) from sys.extended_properties prop
	where prop.major_id = object_id(@sch_name + '.' + @table_name) 
	and prop.name = 'MS_Description' 
	and prop.minor_id = 0;

	if @part is not null
		set @def = @def + char(13) + 'comment on table ' + @full_table_name + ' is ''' + @part + ''';';

--Comments on Fields
  declare
    @comment_column nvarchar(128),
    @comment_value nvarchar(256);
    
	declare cur cursor fast_forward for
		select c.name column_name, cast(cd.value as nvarchar(256)) descr_value
		from        sysobjects t
    /*inner join  sysusers u on u.uid = t.uid*/
		left outer join sys.extended_properties td
			on      td.major_id = t.id
			and     td.minor_id = 0
			and     td.name = 'MS_Description'
		inner join  syscolumns c
			on      c.id = t.id
		left outer join sys.extended_properties cd
			on      cd.major_id = c.id
			and     cd.minor_id = c.colid
			and     cd.name = 'MS_Description'
		where t.type = 'U'
		and t.name = @table_name
		order by    c.colorder;

	open cur;
	fetch next from cur into @comment_column, @comment_value;

	while @@fetch_status = 0
	begin
    if @comment_column is not null and @comment_value is not null 
		  set @def = @def + char(13) + 'comment on column ' + @full_table_name + '.' + 
        dbo.camel_to_underlined(@comment_column) + ' is ''' + @comment_value + ''';';
		fetch next from cur into @comment_column, @comment_value;
	end;

	close cur;
	deallocate cur;
--
	print @def;
end;


