
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

IF OBJECT_ID('sp_ConsultarPlanillaSemanal', 'P') IS NOT NULL DROP PROCEDURE sp_ConsultarPlanillaSemanal;
GO
CREATE PROCEDURE sp_ConsultarPlanillaSemanal
    @IdEmpleado     INT,
    @IdUsuario      INT,
    @IPOrigen       VARCHAR(45),
    @TopSemanas     INT = 10
AS
BEGIN
    SET NOCOUNT ON;
 

    SELECT TOP (@TopSemanas)
        sp.IdSemanaPlanilla,
        sp.FechaInicio,
        sp.FechaFin,
        pse.IdPlanillaSemXEmpleado,
        pse.SalarioBruto,
        pse.TotalDeducciones,
        pse.SalarioNeto,
        pse.HorasOrdinarias,
        pse.HorasExtraNormales,
        pse.HorasExtraDobles
    FROM dbo.PlanillaSemXEmpleado pse
    INNER JOIN dbo.SemanaPlanilla sp ON pse.IdSemanaPlanilla = sp.IdSemanaPlanilla
    WHERE pse.IdEmpleado = @IdEmpleado
    ORDER BY sp.FechaInicio DESC;
 
    DECLARE @params NVARCHAR(200) = '{"empleado_id":' + CAST(@IdEmpleado AS VARCHAR) + '}';
    EXEC sp_RegistrarEvento @IdUsuario, 20, @IPOrigen, @params;
END;
GO
 

IF OBJECT_ID('sp_DetalleDeducciones', 'P') IS NOT NULL DROP PROCEDURE sp_DetalleDeducciones;
GO
CREATE PROCEDURE sp_DetalleDeducciones
    @IdPlanillaSemXEmpleado INT
AS
BEGIN
    SET NOCOUNT ON;
 
    SELECT
        td.Nombre           AS NombreDeduccion,
        td.EsPorcentual,
        CASE WHEN td.EsPorcentual = 1 THEN td.Valor * 100 ELSE NULL END AS Porcentaje,
        ABS(mp.Monto)       AS MontoDeduccion
    FROM dbo.MovimientoPlanilla mp
    INNER JOIN dbo.TipoMovimiento tm ON mp.IdTipoMovimiento = tm.IdTipoMovimiento

    INNER JOIN dbo.TipoDeduccion td ON (mp.IdTipoMovimiento - 3) = td.IdTipoDeduccion
    WHERE mp.IdPlanillaSemXEmpleado = @IdPlanillaSemXEmpleado
      AND tm.Accion = '-'
    ORDER BY td.Nombre;
END;
GO
 

IF OBJECT_ID('sp_DetalleAsistenciaSemanal', 'P') IS NOT NULL DROP PROCEDURE sp_DetalleAsistenciaSemanal;
GO
CREATE PROCEDURE sp_DetalleAsistenciaSemanal
    @IdPlanillaSemXEmpleado INT
AS
BEGIN
    SET NOCOUNT ON;
 
    SELECT
        ma.FechaHoraEntrada,
        ma.FechaHoraSalida,
        tm.Nombre           AS TipoMovimiento,
        mp.Cantidad         AS Horas,
        mp.Monto
    FROM dbo.MovimientoPlanilla mp
    INNER JOIN dbo.TipoMovimiento tm ON mp.IdTipoMovimiento = tm.IdTipoMovimiento
    LEFT  JOIN dbo.MarcaAsistencia ma ON mp.IdMarcaAsistencia = ma.IdMarcaAsistencia
    WHERE mp.IdPlanillaSemXEmpleado = @IdPlanillaSemXEmpleado
      AND tm.Accion = '+'
      AND mp.IdMarcaAsistencia IS NOT NULL
    ORDER BY ma.FechaHoraEntrada;
END;
GO
 
IF OBJECT_ID('sp_ConsultarPlanillaMensual', 'P') IS NOT NULL DROP PROCEDURE sp_ConsultarPlanillaMensual;
GO
CREATE PROCEDURE sp_ConsultarPlanillaMensual
    @IdEmpleado     INT,
    @IdUsuario      INT,
    @IPOrigen       VARCHAR(45),
    @TopMeses       INT = 12
AS
BEGIN
    SET NOCOUNT ON;
 
    SELECT TOP (@TopMeses)
        mp.IdMesPlanilla,
        mp.FechaInicio,
        mp.FechaFin,
        pme.IdPlanillaMesXEmpleado,
        pme.SalarioBrutoMensual,
        pme.TotalDeduccionesMensual,
        pme.SalarioNetoMensual
    FROM dbo.PlanillaMesXEmpleado pme
    INNER JOIN dbo.MesPlanilla mp ON pme.IdMesPlanilla = mp.IdMesPlanilla
    WHERE pme.IdEmpleado = @IdEmpleado
    ORDER BY mp.FechaInicio DESC;
    DECLARE @params NVARCHAR(200) = '{"empleado_id":' + CAST(@IdEmpleado AS VARCHAR) + '}';
    EXEC sp_RegistrarEvento @IdUsuario, 21, @IPOrigen, @params;
END;
GO

IF OBJECT_ID('sp_DetalleDeduccionesMensuales', 'P') IS NOT NULL DROP PROCEDURE sp_DetalleDeduccionesMensuales;
GO
CREATE PROCEDURE sp_DetalleDeduccionesMensuales
    @IdPlanillaMesXEmpleado INT
AS
BEGIN
    SET NOCOUNT ON;
 
    SELECT
        td.Nombre               AS NombreDeduccion,
        td.EsPorcentual,
        CASE WHEN td.EsPorcentual = 1 THEN td.Valor * 100 ELSE NULL END AS Porcentaje,
        dxm.MontoTotal
    FROM dbo.DeduccionXEmpleadoXMes dxm
    INNER JOIN dbo.TipoDeduccion td ON dxm.IdTipoDeduccion = td.IdTipoDeduccion
    WHERE dxm.IdPlanillaMesXEmpleado = @IdPlanillaMesXEmpleado
    ORDER BY td.Nombre;
END;
GO
 

IF OBJECT_ID('sp_InsertarEmpleado', 'P') IS NOT NULL DROP PROCEDURE sp_InsertarEmpleado;
GO
CREATE PROCEDURE sp_InsertarEmpleado
    @Nombre             VARCHAR(150),
    @ValorDocumento     VARCHAR(30),
    @NombrePuesto       VARCHAR(100),  
    @Username           VARCHAR(50),
    @Password           VARCHAR(255),
    @CuentaBancaria     VARCHAR(30) = NULL,
    @FechaIngreso       DATE,
    @IdUsuarioAdmin     INT,
    @IPOrigen           VARCHAR(45),
    @IdEmpleadoNuevo    INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @IdPuesto INT;
        SELECT @IdPuesto = IdPuesto FROM dbo.Puesto WHERE Nombre = @NombrePuesto;
        IF @IdPuesto IS NULL
        BEGIN
            RAISERROR('Puesto "%s" no encontrado.', 16, 1, @NombrePuesto);
            ROLLBACK; RETURN;
        END;
 

        DECLARE @IdUsuarioEmp INT;
        SELECT @IdUsuarioEmp = ISNULL(MAX(IdUsuario), 0) + 1 FROM dbo.Usuario;
        INSERT INTO dbo.Usuario (IdUsuario, Username, PasswordHash, Tipo)
        VALUES (@IdUsuarioEmp, @Username, @Password, 2);
 

        INSERT INTO dbo.Empleado (Nombre, ValorDocumentoIdentidad, IdPuesto, IdUsuario, CuentaBancaria, FechaIngreso, Activo)
        VALUES (@Nombre, @ValorDocumento, @IdPuesto, @IdUsuarioEmp, @CuentaBancaria, @FechaIngreso, 1);
        SET @IdEmpleadoNuevo = SCOPE_IDENTITY();
 

        DECLARE @datos NVARCHAR(MAX) = N'{"nombre":"' + @Nombre + '","doc":"' + @ValorDocumento +
            '","puesto":"' + @NombrePuesto + '","fecha_ingreso":"' + CONVERT(VARCHAR,@FechaIngreso,103) + '"}';
        EXEC sp_RegistrarEvento @IdUsuarioAdmin, 6, @IPOrigen, NULL, NULL, @datos;
 
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        INSERT INTO dbo.DBErrors (NombreSP, Mensaje, Severidad, Estado, Linea)
        VALUES ('sp_InsertarEmpleado', ERROR_MESSAGE(), ERROR_SEVERITY(), ERROR_STATE(), ERROR_LINE());
        DECLARE @msg VARCHAR(500) = ERROR_MESSAGE();
        RAISERROR('Error en sp_InsertarEmpleado: %s', 16, 1, @msg);
    END CATCH;
END;
GO
 
IF OBJECT_ID('sp_EditarEmpleado', 'P') IS NOT NULL DROP PROCEDURE sp_EditarEmpleado;
GO
CREATE PROCEDURE sp_EditarEmpleado
    @IdEmpleado         INT,
    @Nombre             VARCHAR(150),
    @NombrePuesto       VARCHAR(100),
    @CuentaBancaria     VARCHAR(30) = NULL,
    @IdUsuarioAdmin     INT,
    @IPOrigen           VARCHAR(45)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @antes NVARCHAR(MAX);
        SELECT @antes = N'{"nombre":"' + Nombre + '","cuenta":"' + ISNULL(CuentaBancaria,'') + '"}'
        FROM dbo.Empleado WHERE IdEmpleado = @IdEmpleado;
 
        DECLARE @IdPuesto INT;
        SELECT @IdPuesto = IdPuesto FROM dbo.Puesto WHERE Nombre = @NombrePuesto;
 
        UPDATE dbo.Empleado
        SET Nombre         = @Nombre,
            IdPuesto       = ISNULL(@IdPuesto, IdPuesto),
            CuentaBancaria = @CuentaBancaria
        WHERE IdEmpleado = @IdEmpleado;
 
        DECLARE @despues NVARCHAR(MAX);
        SELECT @despues = N'{"nombre":"' + Nombre + '","cuenta":"' + ISNULL(CuentaBancaria,'') + '"}'
        FROM dbo.Empleado WHERE IdEmpleado = @IdEmpleado;
 
        EXEC sp_RegistrarEvento @IdUsuarioAdmin, 8, @IPOrigen,
            N'{"empleado_id":' + CAST(@IdEmpleado AS VARCHAR) + '}',
            @antes, @despues;
 
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        INSERT INTO dbo.DBErrors (NombreSP, Mensaje, Severidad, Estado, Linea)
        VALUES ('sp_EditarEmpleado', ERROR_MESSAGE(), ERROR_SEVERITY(), ERROR_STATE(), ERROR_LINE());
        DECLARE @msg VARCHAR(500) = ERROR_MESSAGE();
        RAISERROR('Error en sp_EditarEmpleado: %s', 16, 1, @msg);
    END CATCH;
END;
GO

    
IF OBJECT_ID('sp_EliminarEmpleado', 'P') IS NOT NULL DROP PROCEDURE sp_EliminarEmpleado;
GO
CREATE PROCEDURE sp_EliminarEmpleado
    @ValorDocumento     VARCHAR(30),
    @IdUsuarioAdmin     INT,
    @IPOrigen           VARCHAR(45)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
 
        DECLARE @IdEmpleado INT;
        DECLARE @datos NVARCHAR(MAX);
 
        SELECT @IdEmpleado = IdEmpleado FROM dbo.Empleado WHERE ValorDocumentoIdentidad = @ValorDocumento AND Activo = 1;
        IF @IdEmpleado IS NULL
        BEGIN
            RAISERROR('Empleado con documento %s no encontrado.', 16, 1, @ValorDocumento);
            ROLLBACK; RETURN;
        END;
 
        SELECT @datos = N'{"empleado_id":' + CAST(IdEmpleado AS VARCHAR) +
            ',"nombre":"' + Nombre + '","doc":"' + ValorDocumento + '"}'
        FROM dbo.Empleado WHERE IdEmpleado = @IdEmpleado;
 
        UPDATE dbo.Empleado SET Activo = 0 WHERE IdEmpleado = @IdEmpleado;
 
 
        EXEC sp_RegistrarEvento @IdUsuarioAdmin, 10, @IPOrigen, NULL, @datos, NULL;
 
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        INSERT INTO dbo.DBErrors (NombreSP, Mensaje, Severidad, Estado, Linea)
        VALUES ('sp_EliminarEmpleado', ERROR_MESSAGE(), ERROR_SEVERITY(), ERROR_STATE(), ERROR_LINE());
        DECLARE @msg VARCHAR(500) = ERROR_MESSAGE();
        RAISERROR('Error en sp_EliminarEmpleado: %s', 16, 1, @msg);
    END CATCH;
END;
GO
 

IF OBJECT_ID('sp_AsociarDeduccion', 'P') IS NOT NULL DROP PROCEDURE sp_AsociarDeduccion;
GO
CREATE PROCEDURE sp_AsociarDeduccion
    @ValorDocumento     VARCHAR(30),
    @IdTipoDeduccion    INT,
    @MontoFijo          DECIMAL(12,2) = 0,
    @FechaInicio        DATE,
    @IdUsuarioAdmin     INT,
    @IPOrigen           VARCHAR(45)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @IdEmpleado INT;
    SELECT @IdEmpleado = IdEmpleado FROM dbo.Empleado WHERE ValorDocumentoIdentidad = @ValorDocumento AND Activo = 1;
 
    INSERT INTO dbo.DeduccionEmpleado (IdEmpleado, IdTipoDeduccion, Valor, FechaInicio, FechaFin)
    VALUES (@IdEmpleado, @IdTipoDeduccion, @MontoFijo, @FechaInicio, NULL);
 

    DECLARE @p NVARCHAR(300) = N'{"empleado_id":' + CAST(@IdEmpleado AS VARCHAR) +
        ',"tipo_deduccion_id":' + CAST(@IdTipoDeduccion AS VARCHAR) +
        ',"monto_fijo":' + CAST(@MontoFijo AS VARCHAR) + '}';
    EXEC sp_RegistrarEvento @IdUsuarioAdmin, 18, @IPOrigen, @p;
END;
GO
 

IF OBJECT_ID('sp_DesasociarDeduccion', 'P') IS NOT NULL DROP PROCEDURE sp_DesasociarDeduccion;
GO
CREATE PROCEDURE sp_DesasociarDeduccion
    @ValorDocumento     VARCHAR(30),
    @IdTipoDeduccion    INT,
    @FechaFin           DATE,
    @IdUsuarioAdmin     INT,
    @IPOrigen           VARCHAR(45)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @IdEmpleado INT;
    SELECT @IdEmpleado = IdEmpleado FROM dbo.Empleado WHERE ValorDocumentoIdentidad = @ValorDocumento AND Activo = 1;
 

    UPDATE dbo.DeduccionEmpleado
    SET FechaFin = @FechaFin
    WHERE IdEmpleado = @IdEmpleado
      AND IdTipoDeduccion = @IdTipoDeduccion
      AND FechaFin IS NULL;
 

    DECLARE @p NVARCHAR(200) = N'{"empleado_id":' + CAST(@IdEmpleado AS VARCHAR) +
        ',"tipo_deduccion_id":' + CAST(@IdTipoDeduccion AS VARCHAR) + '}';
    EXEC sp_RegistrarEvento @IdUsuarioAdmin, 19, @IPOrigen, @p;
END;
GO
 

IF OBJECT_ID('sp_ImpersonarEmpleado', 'P') IS NOT NULL DROP PROCEDURE sp_ImpersonarEmpleado;
GO
CREATE PROCEDURE sp_ImpersonarEmpleado
    @IdEmpleado     INT,
    @IdUsuarioAdmin INT,
    @IPOrigen       VARCHAR(45)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @p NVARCHAR(100) = N'{"empleado_id":' + CAST(@IdEmpleado AS VARCHAR) + '}';
    EXEC sp_RegistrarEvento @IdUsuarioAdmin, 15, @IPOrigen, @p;
END;
GO
 
IF OBJECT_ID('sp_RegresarAdmin', 'P') IS NOT NULL DROP PROCEDURE sp_RegresarAdmin;
GO
CREATE PROCEDURE sp_RegresarAdmin
    @IdUsuarioAdmin INT,
    @IPOrigen       VARCHAR(45)
AS
BEGIN
    SET NOCOUNT ON;
    EXEC sp_RegistrarEvento @IdUsuarioAdmin, 16, @IPOrigen, NULL;
END;
GO
 
PRINT 'SPs de consultas y CRUD creados exitosamente.';
GO   
