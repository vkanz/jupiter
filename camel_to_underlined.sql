USE [ShturmanDiagnostics]
GO
/****** Object:  UserDefinedFunction [dbo].[camel_to_underlined]    Script Date: 16.08.2019 18:29:16 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER function [dbo].[camel_to_underlined](
  @src varchar(128)
  )
  returns varchar(128)
as
begin
  declare 
    @len int = len(@src),
    @i int = 1,
    @curr varchar(1),
    @prev varchar(1),
    @dst varchar(128);

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
  return lower(@dst);   
end;