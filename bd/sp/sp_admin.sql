USE PlanillaObrera;
GO

SET ANSI_NULLS ON;
GO

SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.sp_DesasociarDeduccion', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_DesasociarDeduccion;
GO

IF OBJECT_ID('dbo.sp_AsociarDeduccion', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_AsociarDeduccion;
GO

IF OBJECT_ID('dbo.sp_EliminarEmpleado', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_EliminarEmpleado;
GO

IF OBJECT_ID('dbo.sp_InsertarEmpleado', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_InsertarEmpleado;
GO

CREATE PROCEDURE dbo.sp_InsertarEmpleado
    @inNombre VARCHAR(150)
  ,@inValorDocumento VARCHAR(30)
  ,@inNombrePuesto VARCHAR(100)
  ,@inUsername VARCHAR(50)
  ,@inPassword VARCHAR(255)
  ,@inCuentaBancaria VARCHAR(30)
  ,@inFechaIngreso DATE
  ,@inIdUsuarioAdmin INT
  ,@inIPOrigen VARCHAR(45) = '127.0.0.1'
  ,@outIdEmpleadoNuevo INT OUTPUT
  ,@outResultCode INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @outResultCode = 0;
    SET @outIdEmpleadoNuevo = NULL;

    DECLARE @vIdPuesto INT;
    DECLARE @vIdUsuarioNuevo INT;
    DECLARE @vParametros NVARCHAR(MAX);
    DECLARE @vDatosDespues NVARCHAR(MAX);

    SELECT
        @vIdPuesto = p.IdPuesto
    FROM dbo.Puesto AS p
    WHERE (p.Nombre = @inNombrePuesto);

    IF (@vIdPuesto IS NULL)
    BEGIN
        SET @outResultCode = 50008;
        RETURN;
    END;

    IF EXISTS (
        SELECT 1
        FROM dbo.Empleado AS e
        WHERE (e.ValorDocumentoIdentidad = @inValorDocumento)
    )
    BEGIN
        SET @outResultCode = 50004;
        RETURN;
    END;

    IF EXISTS (
        SELECT 1
        FROM dbo.Empleado AS e
        WHERE (e.Nombre = @inNombre)
    )
    BEGIN
        SET @outResultCode = 50005;
        RETURN;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT
            @vIdUsuarioNuevo = ISNULL(MAX(u.IdUsuario), 0) + 1
        FROM dbo.Usuario AS u WITH (UPDLOCK, HOLDLOCK);

        INSERT INTO dbo.Usuario (
            IdUsuario
          , Username
          , PasswordHash
          , Tipo
          , Activo
        )
        VALUES (
            @vIdUsuarioNuevo
          ,@inUsername
          ,@inPassword
          , 2
          , 1
        );

        INSERT INTO dbo.Empleado (
            Nombre
          , ValorDocumentoIdentidad
          , IdPuesto
          , IdUsuario
          , CuentaBancaria
          , FechaIngreso
          , Activo
        )
        VALUES (
            @inNombre
          ,@inValorDocumento
          ,@vIdPuesto
          ,@vIdUsuarioNuevo
          ,@inCuentaBancaria
          ,@inFechaIngreso
          , 1
        );

        SET @outIdEmpleadoNuevo = SCOPE_IDENTITY();

        SET @vParametros = CONCAT(
            N'{"valorDocumento":"'
          ,@inValorDocumento
          , N'"}'
        );

        SET @vDatosDespues = CONCAT(
            N'{"idEmpleado":'
          ,@outIdEmpleadoNuevo
          , N',"nombre":"'
          ,@inNombre
          , N'","valorDocumento":"'
          ,@inValorDocumento
          , N'","puesto":"'
          ,@inNombrePuesto
          , N'"}'
        );

        INSERT INTO dbo.BitacoraEvento (
            IdUsuario
          , IdTipoEvento
          , IPOrigen
          , Parametros
          , DatosDespues
        )
        VALUES (
            @inIdUsuarioAdmin
          , 6
          ,@inIPOrigen
          ,@vParametros
          ,@vDatosDespues
        );

        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH

        IF (@@TRANCOUNT > 0)
            ROLLBACK TRANSACTION;

        SET @outResultCode = 50008;

        INSERT INTO dbo.DBErrors (
            NombreSP
          , Mensaje
          , Severidad
          , Estado
          , Linea
        )
        VALUES (
            'sp_InsertarEmpleado'
          , ERROR_MESSAGE()
          , ERROR_SEVERITY()
          , ERROR_STATE()
          , ERROR_LINE()
        );

    END CATCH;
END;
GO

CREATE PROCEDURE dbo.sp_EliminarEmpleado
    @inValorDocumento VARCHAR(30)
  ,@inIdUsuarioAdmin INT
  ,@inIPOrigen VARCHAR(45) = '127.0.0.1'
  ,@outResultCode INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @outResultCode = 0;

    DECLARE @vIdEmpleado INT;
    DECLARE @vIdUsuario INT;
    DECLARE @vDatosAntes NVARCHAR(MAX);
    DECLARE @vParametros NVARCHAR(MAX);

    SELECT
        @vIdEmpleado = e.IdEmpleado
      ,@vIdUsuario = e.IdUsuario
      ,@vDatosAntes = CONCAT(
            N'{"idEmpleado":'
          , e.IdEmpleado
          , N',"nombre":"'
          , e.Nombre
          , N'","valorDocumento":"'
          , e.ValorDocumentoIdentidad
          , N'","activo":'
          , CONVERT(VARCHAR(1), e.Activo)
          , N'}'
        )
    FROM dbo.Empleado AS e
    WHERE (e.ValorDocumentoIdentidad = @inValorDocumento)
      AND (e.Activo = 1);

    IF (@vIdEmpleado IS NULL)
    BEGIN
        SET @outResultCode = 50008;
        RETURN;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE dbo.DeduccionEmpleado
        SET FechaFin = CAST(GETDATE() AS DATE)
        WHERE (IdEmpleado = @vIdEmpleado)
          AND (FechaFin IS NULL);

        UPDATE dbo.Empleado
        SET Activo = 0
        WHERE (IdEmpleado = @vIdEmpleado);

        UPDATE dbo.Usuario
        SET Activo = 0
        WHERE (IdUsuario = @vIdUsuario);

        SET @vParametros = CONCAT(
            N'{"valorDocumento":"'
          ,@inValorDocumento
          , N'"}'
        );

        INSERT INTO dbo.BitacoraEvento (
            IdUsuario
          , IdTipoEvento
          , IPOrigen
          , Parametros
          , DatosAntes
        )
        VALUES (
            @inIdUsuarioAdmin
          , 10
          ,@inIPOrigen
          ,@vParametros
          ,@vDatosAntes
        );

        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH

        IF (@@TRANCOUNT > 0)
            ROLLBACK TRANSACTION;

        SET @outResultCode = 50008;

        INSERT INTO dbo.DBErrors (
            NombreSP
          , Mensaje
          , Severidad
          , Estado
          , Linea
        )
        VALUES (
            'sp_EliminarEmpleado'
          , ERROR_MESSAGE()
          , ERROR_SEVERITY()
          , ERROR_STATE()
          , ERROR_LINE()
        );

    END CATCH;
END;
GO

CREATE PROCEDURE dbo.sp_AsociarDeduccion
    @inValorDocumento VARCHAR(30)
  ,@inIdTipoDeduccion INT
  ,@inMontoFijo DECIMAL(12,2)
  ,@inFechaInicio DATE
  ,@inIdUsuarioAdmin INT
  ,@inIPOrigen VARCHAR(45) = '127.0.0.1'
  ,@outResultCode INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @outResultCode = 0;

    DECLARE @vIdEmpleado INT;
    DECLARE @vValor DECIMAL(10,4);
    DECLARE @vParametros NVARCHAR(MAX);
    DECLARE @vDatosDespues NVARCHAR(MAX);

    SELECT
        @vIdEmpleado = e.IdEmpleado
    FROM dbo.Empleado AS e
    WHERE (e.ValorDocumentoIdentidad = @inValorDocumento)
      AND (e.Activo = 1);

    IF (@vIdEmpleado IS NULL)
    BEGIN
        SET @outResultCode = 50008;
        RETURN;
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.TipoDeduccion AS td
        WHERE (td.IdTipoDeduccion = @inIdTipoDeduccion)
          AND (td.EsObligatoria = 0)
    )
    BEGIN
        SET @outResultCode = 50008;
        RETURN;
    END;

    IF EXISTS (
        SELECT 1
        FROM dbo.DeduccionEmpleado AS de
        WHERE (de.IdEmpleado = @vIdEmpleado)
          AND (de.IdTipoDeduccion = @inIdTipoDeduccion)
          AND (de.FechaFin IS NULL)
    )
    BEGIN
        SET @outResultCode = 0;
        RETURN;
    END;

    SELECT
        @vValor = CASE
            WHEN (td.EsPorcentual = 1) THEN td.Valor
            ELSE CONVERT(DECIMAL(10,4), @inMontoFijo)
        END
    FROM dbo.TipoDeduccion AS td
    WHERE (td.IdTipoDeduccion = @inIdTipoDeduccion);

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO dbo.DeduccionEmpleado (
            IdEmpleado
          , IdTipoDeduccion
          , Valor
          , FechaInicio
          , FechaFin
        )
        VALUES (
            @vIdEmpleado
          ,@inIdTipoDeduccion
          ,@vValor
          ,@inFechaInicio
          , NULL
        );

        SET @vParametros = CONCAT(
            N'{"valorDocumento":"'
          ,@inValorDocumento
          , N'","idTipoDeduccion":'
          ,@inIdTipoDeduccion
          , N'}'
        );

        SET @vDatosDespues = CONCAT(
            N'{"idEmpleado":'
          ,@vIdEmpleado
          , N',"idTipoDeduccion":'
          ,@inIdTipoDeduccion
          , N',"valor":'
          ,@vValor
          , N'}'
        );

        INSERT INTO dbo.BitacoraEvento (
            IdUsuario
          , IdTipoEvento
          , IPOrigen
          , Parametros
          , DatosDespues
        )
        VALUES (
            @inIdUsuarioAdmin
          , 8
          ,@inIPOrigen
          ,@vParametros
          ,@vDatosDespues
        );

        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH

        IF (@@TRANCOUNT > 0)
            ROLLBACK TRANSACTION;

        SET @outResultCode = 50008;

        INSERT INTO dbo.DBErrors (
            NombreSP
          , Mensaje
          , Severidad
          , Estado
          , Linea
        )
        VALUES (
            'sp_AsociarDeduccion'
          , ERROR_MESSAGE()
          , ERROR_SEVERITY()
          , ERROR_STATE()
          , ERROR_LINE()
        );

    END CATCH;
END;
GO

CREATE PROCEDURE dbo.sp_DesasociarDeduccion
    @inValorDocumento VARCHAR(30)
  ,@inIdTipoDeduccion INT
  ,@inFechaFin DATE
  ,@inIdUsuarioAdmin INT
  ,@inIPOrigen VARCHAR(45) = '127.0.0.1'
  ,@outResultCode INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @outResultCode = 0;

    DECLARE @vIdEmpleado INT;
    DECLARE @vDatosAntes NVARCHAR(MAX);
    DECLARE @vParametros NVARCHAR(MAX);

    SELECT
        @vIdEmpleado = e.IdEmpleado
    FROM dbo.Empleado AS e
    WHERE (e.ValorDocumentoIdentidad = @inValorDocumento)
      AND (e.Activo = 1);

    IF (@vIdEmpleado IS NULL)
    BEGIN
        SET @outResultCode = 50008;
        RETURN;
    END;

    SELECT TOP (1)
        @vDatosAntes = CONCAT(
            N'{"idEmpleado":'
          , de.IdEmpleado
          , N',"idTipoDeduccion":'
          , de.IdTipoDeduccion
          , N',"valor":'
          , de.Valor
          , N'}'
        )
    FROM dbo.DeduccionEmpleado AS de
    WHERE (de.IdEmpleado = @vIdEmpleado)
      AND (de.IdTipoDeduccion = @inIdTipoDeduccion)
      AND (de.FechaFin IS NULL);

    IF (@vDatosAntes IS NULL)
    BEGIN
        SET @outResultCode = 0;
        RETURN;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE dbo.DeduccionEmpleado
        SET FechaFin = @inFechaFin
        WHERE (IdEmpleado = @vIdEmpleado)
          AND (IdTipoDeduccion = @inIdTipoDeduccion)
          AND (FechaFin IS NULL);

        SET @vParametros = CONCAT(
            N'{"valorDocumento":"'
          ,@inValorDocumento
          , N'","idTipoDeduccion":'
          ,@inIdTipoDeduccion
          , N'}'
        );

        INSERT INTO dbo.BitacoraEvento (
            IdUsuario
          , IdTipoEvento
          , IPOrigen
          , Parametros
          , DatosAntes
        )
        VALUES (
            @inIdUsuarioAdmin
          , 8
          ,@inIPOrigen
          ,@vParametros
          ,@vDatosAntes
        );

        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH

        IF (@@TRANCOUNT > 0)
            ROLLBACK TRANSACTION;

        SET @outResultCode = 50008;

        INSERT INTO dbo.DBErrors (
            NombreSP
          , Mensaje
          , Severidad
          , Estado
          , Linea
        )
        VALUES (
            'sp_DesasociarDeduccion'
          , ERROR_MESSAGE()
          , ERROR_SEVERITY()
          , ERROR_STATE()
          , ERROR_LINE()
        );

    END CATCH;
END;
GO

PRINT 'SPs administrativos creados exitosamente.';
GO
