USE PlanillaObrera;
GO

SET ANSI_NULLS ON;
GO

SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.sp_ActualizarEmpleado', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_ActualizarEmpleado;
GO

IF OBJECT_ID('dbo.sp_ObtenerEmpleado', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_ObtenerEmpleado;
GO

IF OBJECT_ID('dbo.sp_ListarEmpleadosConFiltro', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_ListarEmpleadosConFiltro;
GO

IF OBJECT_ID('dbo.sp_ListarEmpleados', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_ListarEmpleados;
GO

IF OBJECT_ID('dbo.sp_Login', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Login;
GO

CREATE PROCEDURE dbo.sp_Login
    @inUsername      VARCHAR(50)
  , @inPassword      VARCHAR(255)
  , @inIPOrigen      VARCHAR(45) = '127.0.0.1'
  , @outIdUsuario    INT OUTPUT
  , @outTipoUsuario  TINYINT OUTPUT
  , @outResultCode   INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @outResultCode = 0;
    SET @outIdUsuario = NULL;
    SET @outTipoUsuario = NULL;

    BEGIN TRY
        SELECT
            @outIdUsuario = u.IdUsuario
          , @outTipoUsuario = u.Tipo
        FROM dbo.Usuario AS u
        WHERE (u.Username = @inUsername);

        IF (@outIdUsuario IS NULL)
        BEGIN
            SET @outResultCode = 50001;
            RETURN;
        END;

        IF EXISTS (
            SELECT 1
            FROM dbo.Usuario AS u
            WHERE (u.IdUsuario = @outIdUsuario)
              AND (u.Activo = 0)
        )
        BEGIN
            INSERT INTO dbo.BitacoraEvento (
                IdUsuario
              , IdTipoEvento
              , IPOrigen
              , Parametros
            )
            VALUES (
                @outIdUsuario
              , 3
              , @inIPOrigen
              , CONCAT(N'{"username":"', @inUsername, N'"}')
            );

            SET @outResultCode = 50003;
            RETURN;
        END;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Usuario AS u
            WHERE (u.IdUsuario = @outIdUsuario)
              AND (u.PasswordHash = @inPassword)
        )
        BEGIN
            INSERT INTO dbo.BitacoraEvento (
                IdUsuario
              , IdTipoEvento
              , IPOrigen
              , Parametros
            )
            VALUES (
                @outIdUsuario
              , 2
              , @inIPOrigen
              , CONCAT(N'{"username":"', @inUsername, N'"}')
            );

            SET @outResultCode = 50002;
            RETURN;
        END;

        INSERT INTO dbo.BitacoraEvento (
            IdUsuario
          , IdTipoEvento
          , IPOrigen
          , Parametros
        )
        VALUES (
            @outIdUsuario
          , 1
          , @inIPOrigen
          , CONCAT(N'{"username":"', @inUsername, N'"}')
        );

    END TRY
    BEGIN CATCH

        SET @outResultCode = 50008;

        INSERT INTO dbo.DBErrors (
            NombreSP
          , Mensaje
          , Severidad
          , Estado
          , Linea
        )
        VALUES (
            'sp_Login'
          , ERROR_MESSAGE()
          , ERROR_SEVERITY()
          , ERROR_STATE()
          , ERROR_LINE()
        );

    END CATCH;
END;
GO

CREATE PROCEDURE dbo.sp_ListarEmpleados
    @inSoloActivos  BIT = 1
  , @outResultCode  INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @outResultCode = 0;

    BEGIN TRY
        SELECT
            e.IdEmpleado
          , e.Nombre
          , e.ValorDocumentoIdentidad
          , e.CuentaBancaria
          , e.FechaIngreso
          , e.Activo
          , p.IdPuesto
          , p.Nombre AS NombrePuesto
          , p.SalarioXHora
          , u.IdUsuario
          , u.Username
          , u.Tipo AS TipoUsuario
        FROM dbo.Empleado AS e
        INNER JOIN dbo.Puesto AS p
            ON (p.IdPuesto = e.IdPuesto)
        INNER JOIN dbo.Usuario AS u
            ON (u.IdUsuario = e.IdUsuario)
        WHERE (@inSoloActivos = 0 OR e.Activo = 1)
        ORDER BY
            e.Nombre;

    END TRY
    BEGIN CATCH

        SET @outResultCode = 50008;

        INSERT INTO dbo.DBErrors (
            NombreSP
          , Mensaje
          , Severidad
          , Estado
          , Linea
        )
        VALUES (
            'sp_ListarEmpleados'
          , ERROR_MESSAGE()
          , ERROR_SEVERITY()
          , ERROR_STATE()
          , ERROR_LINE()
        );

    END CATCH;
END;
GO

CREATE PROCEDURE dbo.sp_ListarEmpleadosConFiltro
    @inNombre             VARCHAR(150) = NULL
  , @inValorDocumento     VARCHAR(30) = NULL
  , @inSoloActivos        BIT = 1
  , @inIdUsuarioConsulta  INT = NULL
  , @inIPOrigen           VARCHAR(45) = '127.0.0.1'
  , @outResultCode        INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @outResultCode = 0;

    BEGIN TRY
        SELECT
            e.IdEmpleado
          , e.Nombre
          , e.ValorDocumentoIdentidad
          , e.CuentaBancaria
          , e.FechaIngreso
          , e.Activo
          , p.IdPuesto
          , p.Nombre AS NombrePuesto
          , p.SalarioXHora
          , u.IdUsuario
          , u.Username
          , u.Tipo AS TipoUsuario
        FROM dbo.Empleado AS e
        INNER JOIN dbo.Puesto AS p
            ON (p.IdPuesto = e.IdPuesto)
        INNER JOIN dbo.Usuario AS u
            ON (u.IdUsuario = e.IdUsuario)
        WHERE (@inSoloActivos = 0 OR e.Activo = 1)
          AND (@inNombre IS NULL OR e.Nombre LIKE '%' + @inNombre + '%')
          AND (
                @inValorDocumento IS NULL
                OR e.ValorDocumentoIdentidad LIKE '%' + @inValorDocumento + '%'
              )
        ORDER BY
            e.Nombre;

        IF (@inIdUsuarioConsulta IS NOT NULL)
        BEGIN
            IF (@inNombre IS NOT NULL)
            BEGIN
                INSERT INTO dbo.BitacoraEvento (
                    IdUsuario
                  , IdTipoEvento
                  , IPOrigen
                  , Parametros
                )
                VALUES (
                    @inIdUsuarioConsulta
                  , 11
                  , @inIPOrigen
                  , CONCAT(N'{"nombre":"', @inNombre, N'"}')
                );
            END;

            IF (@inValorDocumento IS NOT NULL)
            BEGIN
                INSERT INTO dbo.BitacoraEvento (
                    IdUsuario
                  , IdTipoEvento
                  , IPOrigen
                  , Parametros
                )
                VALUES (
                    @inIdUsuarioConsulta
                  , 12
                  , @inIPOrigen
                  , CONCAT(N'{"valorDocumento":"', @inValorDocumento, N'"}')
                );
            END;
        END;

    END TRY
    BEGIN CATCH

        SET @outResultCode = 50008;

        INSERT INTO dbo.DBErrors (
            NombreSP
          , Mensaje
          , Severidad
          , Estado
          , Linea
        )
        VALUES (
            'sp_ListarEmpleadosConFiltro'
          , ERROR_MESSAGE()
          , ERROR_SEVERITY()
          , ERROR_STATE()
          , ERROR_LINE()
        );

    END CATCH;
END;
GO

CREATE PROCEDURE dbo.sp_ObtenerEmpleado
    @inIdEmpleado        INT = NULL
  , @inValorDocumento    VARCHAR(30) = NULL
  , @outResultCode       INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @outResultCode = 0;

    BEGIN TRY
        SELECT
            e.IdEmpleado
          , e.Nombre
          , e.ValorDocumentoIdentidad
          , e.CuentaBancaria
          , e.FechaIngreso
          , e.Activo
          , p.IdPuesto
          , p.Nombre AS NombrePuesto
          , p.SalarioXHora
          , u.IdUsuario
          , u.Username
          , u.Tipo AS TipoUsuario
        FROM dbo.Empleado AS e
        INNER JOIN dbo.Puesto AS p
            ON (p.IdPuesto = e.IdPuesto)
        INNER JOIN dbo.Usuario AS u
            ON (u.IdUsuario = e.IdUsuario)
        WHERE (@inIdEmpleado IS NOT NULL AND e.IdEmpleado = @inIdEmpleado)
           OR (@inValorDocumento IS NOT NULL AND e.ValorDocumentoIdentidad = @inValorDocumento);

    END TRY
    BEGIN CATCH

        SET @outResultCode = 50008;

        INSERT INTO dbo.DBErrors (
            NombreSP
          , Mensaje
          , Severidad
          , Estado
          , Linea
        )
        VALUES (
            'sp_ObtenerEmpleado'
          , ERROR_MESSAGE()
          , ERROR_SEVERITY()
          , ERROR_STATE()
          , ERROR_LINE()
        );

    END CATCH;
END;
GO

CREATE PROCEDURE dbo.sp_ActualizarEmpleado
    @inIdEmpleado        INT
  , @inNombre            VARCHAR(150)
  , @inValorDocumento    VARCHAR(30)
  , @inNombrePuesto      VARCHAR(100)
  , @inUsername          VARCHAR(50)
  , @inPassword          VARCHAR(255) = NULL
  , @inCuentaBancaria    VARCHAR(30) = NULL
  , @inFechaIngreso      DATE
  , @inActivo            BIT = 1
  , @inIdUsuarioAdmin    INT
  , @inIPOrigen          VARCHAR(45) = '127.0.0.1'
  , @outResultCode       INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @outResultCode = 0;

    DECLARE @vIdPuesto      INT;
    DECLARE @vIdUsuario     INT;
    DECLARE @vDatosAntes    NVARCHAR(MAX);
    DECLARE @vDatosDespues  NVARCHAR(MAX);
    DECLARE @vParametros    NVARCHAR(MAX);

    BEGIN TRY
        SELECT
            @vIdPuesto = p.IdPuesto
        FROM dbo.Puesto AS p
        WHERE (p.Nombre = @inNombrePuesto);

        IF (@vIdPuesto IS NULL)
        BEGIN
            SET @outResultCode = 50008;
            RETURN;
        END;

        SELECT
            @vIdUsuario = e.IdUsuario
          , @vDatosAntes = CONCAT(
                N'{"idEmpleado":'
              , e.IdEmpleado
              , N',"nombre":"'
              , e.Nombre
              , N'","valorDocumento":"'
              , e.ValorDocumentoIdentidad
              , N'","idPuesto":'
              , e.IdPuesto
              , N',"cuentaBancaria":"'
              , ISNULL(e.CuentaBancaria, '')
              , N'","fechaIngreso":"'
              , CONVERT(VARCHAR(10), e.FechaIngreso, 120)
              , N'","activo":'
              , CONVERT(VARCHAR(1), e.Activo)
              , N'}'
            )
        FROM dbo.Empleado AS e
        WHERE (e.IdEmpleado = @inIdEmpleado);

        IF (@vIdUsuario IS NULL)
        BEGIN
            SET @outResultCode = 50008;
            RETURN;
        END;

        IF EXISTS (
            SELECT 1
            FROM dbo.Empleado AS e
            WHERE (e.ValorDocumentoIdentidad = @inValorDocumento)
              AND (e.IdEmpleado <> @inIdEmpleado)
        )
        BEGIN
            SET @outResultCode = 50006;
            RETURN;
        END;

        IF EXISTS (
            SELECT 1
            FROM dbo.Empleado AS e
            WHERE (e.Nombre = @inNombre)
              AND (e.IdEmpleado <> @inIdEmpleado)
        )
        BEGIN
            SET @outResultCode = 50007;
            RETURN;
        END;

        BEGIN TRANSACTION;

        UPDATE dbo.Usuario
        SET Username = @inUsername
          , PasswordHash = COALESCE(@inPassword, PasswordHash)
          , Activo = @inActivo
        WHERE (IdUsuario = @vIdUsuario);

        UPDATE dbo.Empleado
        SET Nombre = @inNombre
          , ValorDocumentoIdentidad = @inValorDocumento
          , IdPuesto = @vIdPuesto
          , CuentaBancaria = @inCuentaBancaria
          , FechaIngreso = @inFechaIngreso
          , Activo = @inActivo
        WHERE (IdEmpleado = @inIdEmpleado);

        SET @vParametros = CONCAT(
            N'{"idEmpleado":'
          , @inIdEmpleado
          , N'}'
        );

        SET @vDatosDespues = CONCAT(
            N'{"idEmpleado":'
          , @inIdEmpleado
          , N',"nombre":"'
          , @inNombre
          , N'","valorDocumento":"'
          , @inValorDocumento
          , N'","puesto":"'
          , @inNombrePuesto
          , N'","cuentaBancaria":"'
          , ISNULL(@inCuentaBancaria, '')
          , N'","fechaIngreso":"'
          , CONVERT(VARCHAR(10), @inFechaIngreso, 120)
          , N'","activo":'
          , CONVERT(VARCHAR(1), @inActivo)
          , N'}'
        );

        INSERT INTO dbo.BitacoraEvento (
            IdUsuario
          , IdTipoEvento
          , IPOrigen
          , Parametros
          , DatosAntes
          , DatosDespues
        )
        VALUES (
            @inIdUsuarioAdmin
          , 8
          , @inIPOrigen
          , @vParametros
          , @vDatosAntes
          , @vDatosDespues
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
            'sp_ActualizarEmpleado'
          , ERROR_MESSAGE()
          , ERROR_SEVERITY()
          , ERROR_STATE()
          , ERROR_LINE()
        );

    END CATCH;
END;
GO

PRINT 'SPs de consultas creados exitosamente.';
GO
