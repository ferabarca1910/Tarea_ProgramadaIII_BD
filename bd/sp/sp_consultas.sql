
USE PlanillaObrera;
GO

IF OBJECT_ID('sp_Login', 'P') IS NOT NULL DROP PROCEDURE sp_Login;
GO
CREATE PROCEDURE sp_Login
    @Username   VARCHAR(50),
    @Password   VARCHAR(255),
    @IPOrigen   VARCHAR(45),
    @IdUsuario  INT OUTPUT,
    @Tipo TINYINT OUTPUT,
    @Exitoso    BIT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
 
    SELECT
        @IdUsuario   = IdUsuario,
        @Tipo = Tipo
    FROM dbo.Usuario
    WHERE Username = @Username
      AND PasswordHash = @Password  
      AND Activo = 1;
 
    IF @IdUsuario IS NOT NULL
    BEGIN
        SET @Exitoso = 1;
        EXEC sp_RegistrarEvento @IdUsuario, 1, @IPOrigen,
            N'{"username":"' + @Username + '","resultado":"exitoso"}';
    END
    ELSE
    BEGIN
        SET @Exitoso = 0;
        -- Registrar intento fallido con IdUsuario=0 (sistema)
        EXEC sp_RegistrarEvento 1, 2, @IPOrigen,
            N'{"username":"' + @Username + '","resultado":"fallido"}';
    END;
END;
GO
 
IF OBJECT_ID('sp_Logout', 'P') IS NOT NULL DROP PROCEDURE sp_Logout;
GO
CREATE PROCEDURE sp_Logout
    @IdUsuario  INT,
    @IPOrigen   VARCHAR(45)
AS
BEGIN
    SET NOCOUNT ON;
    EXEC sp_RegistrarEvento @IdUsuario, 11, @IPOrigen, NULL;
END;
GO
 
IF OBJECT_ID('sp_ListarEmpleados', 'P') IS NOT NULL DROP PROCEDURE sp_ListarEmpleados;
GO
CREATE PROCEDURE sp_ListarEmpleados
    @IdUsuario  INT,
    @IPOrigen   VARCHAR(45),
    @Filtro     VARCHAR(150) = NULL   
AS
BEGIN
    SET NOCOUNT ON;
 
    SELECT
        e.IdEmpleado,
        e.Nombre,
        p.Nombre                    AS NombrePuesto,
        e.ValorDocumentoIdentidad,
        e.FechaIngreso
    FROM dbo.Empleado e
    INNER JOIN dbo.Puesto p ON e.IdPuesto = p.IdPuesto
    WHERE e.Activo = 1
      AND (@Filtro IS NULL OR e.Nombre LIKE '%' + @Filtro + '%')
    ORDER BY e.Nombre;
 
    IF @Filtro IS NULL
        EXEC sp_RegistrarEvento @IdUsuario, 17, @IPOrigen, NULL;                         
    ELSE
        EXEC sp_RegistrarEvento @IdUsuario, 11, @IPOrigen,
            N'{"filtro":"' + @Filtro + '"}';                                             
END;
GO
 
