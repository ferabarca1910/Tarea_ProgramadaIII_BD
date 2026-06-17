USE PlanillaObrera;
GO

SET ANSI_NULLS ON;
GO

SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.sp_ConsultarDetalleDeduccionesMes', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_ConsultarDetalleDeduccionesMes;
GO

IF OBJECT_ID('dbo.sp_WebConsultarDetalleDeduccionesMes', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_WebConsultarDetalleDeduccionesMes;
GO

IF OBJECT_ID('dbo.sp_WebConsultarPlanillaMensual', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_WebConsultarPlanillaMensual;
GO

IF OBJECT_ID('dbo.sp_WebConsultarDetalleHorasSemana', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_WebConsultarDetalleHorasSemana;
GO

IF OBJECT_ID('dbo.sp_WebConsultarDetalleDeduccionesSemana', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_WebConsultarDetalleDeduccionesSemana;
GO

IF OBJECT_ID('dbo.sp_WebConsultarPlanillaSemanal', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_WebConsultarPlanillaSemanal;
GO

IF OBJECT_ID('dbo.sp_WebRegistrarEventoBitacora', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_WebRegistrarEventoBitacora;
GO

IF OBJECT_ID('dbo.sp_WebEliminarEmpleado', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_WebEliminarEmpleado;
GO

IF OBJECT_ID('dbo.sp_WebActualizarEmpleado', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_WebActualizarEmpleado;
GO

IF OBJECT_ID('dbo.sp_WebInsertarEmpleado', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_WebInsertarEmpleado;
GO

IF OBJECT_ID('dbo.sp_WebListarPuestos', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_WebListarPuestos;
GO

IF OBJECT_ID('dbo.sp_WebObtenerEmpleadoPorUsuario', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_WebObtenerEmpleadoPorUsuario;
GO

IF OBJECT_ID('dbo.sp_WebObtenerEmpleado', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_WebObtenerEmpleado;
GO

IF OBJECT_ID('dbo.sp_WebListarEmpleadosConFiltro', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_WebListarEmpleadosConFiltro;
GO

IF OBJECT_ID('dbo.sp_WebLogin', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_WebLogin;
GO

IF OBJECT_ID('dbo.sp_ConsultarPlanillaMensual', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_ConsultarPlanillaMensual;
GO

IF OBJECT_ID('dbo.sp_ConsultarDetalleHorasSemana', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_ConsultarDetalleHorasSemana;
GO

IF OBJECT_ID('dbo.sp_ConsultarDetalleDeduccionesSemana', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_ConsultarDetalleDeduccionesSemana;
GO

IF OBJECT_ID('dbo.sp_ConsultarPlanillaSemanal', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_ConsultarPlanillaSemanal;
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
    @inUsername VARCHAR(50)
  ,@inPassword VARCHAR(255)
  ,@inIPOrigen VARCHAR(45) = '127.0.0.1'
  ,@outIdUsuario INT OUTPUT
  ,@outTipoUsuario TINYINT OUTPUT
  ,@outResultCode INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @outResultCode = 0;
    SET @outIdUsuario = NULL;
    SET @outTipoUsuario = NULL;

    BEGIN TRY
        SELECT
            @outIdUsuario = u.IdUsuario
          ,@outTipoUsuario = u.Tipo
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
              ,@inIPOrigen
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
              ,@inIPOrigen
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
          ,@inIPOrigen
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
    @inSoloActivos BIT = 1
  ,@outResultCode INT OUTPUT
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
    @inNombre VARCHAR(150) = NULL
  ,@inValorDocumento VARCHAR(30) = NULL
  ,@inSoloActivos BIT = 1
  ,@inIdUsuarioConsulta INT = NULL
  ,@inIPOrigen VARCHAR(45) = '127.0.0.1'
  ,@outResultCode INT OUTPUT
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
                  ,@inIPOrigen
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
                  ,@inIPOrigen
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
    @inIdEmpleado INT = NULL
  ,@inValorDocumento VARCHAR(30) = NULL
  ,@outResultCode INT OUTPUT
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
    @inIdEmpleado INT
  ,@inNombre VARCHAR(150)
  ,@inValorDocumento VARCHAR(30)
  ,@inNombrePuesto VARCHAR(100)
  ,@inUsername VARCHAR(50)
  ,@inPassword VARCHAR(255) = NULL
  ,@inCuentaBancaria VARCHAR(30) = NULL
  ,@inFechaIngreso DATE
  ,@inActivo BIT = 1
  ,@inIdUsuarioAdmin INT
  ,@inIPOrigen VARCHAR(45) = '127.0.0.1'
  ,@outResultCode INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @outResultCode = 0;

    DECLARE @vIdPuesto INT;
    DECLARE @vIdUsuario INT;
    DECLARE @vDatosAntes NVARCHAR(MAX);
    DECLARE @vDatosDespues NVARCHAR(MAX);
    DECLARE @vParametros NVARCHAR(MAX);

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
          ,@vDatosAntes = CONCAT(
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
          ,@inIdEmpleado
          , N'}'
        );

        SET @vDatosDespues = CONCAT(
            N'{"idEmpleado":'
          ,@inIdEmpleado
          , N',"nombre":"'
          ,@inNombre
          , N'","valorDocumento":"'
          ,@inValorDocumento
          , N'","puesto":"'
          ,@inNombrePuesto
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
          ,@inIPOrigen
          ,@vParametros
          ,@vDatosAntes
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
            'sp_ActualizarEmpleado'
          , ERROR_MESSAGE()
          , ERROR_SEVERITY()
          , ERROR_STATE()
          , ERROR_LINE()
        );

    END CATCH;
END;
GO

CREATE PROCEDURE dbo.sp_ConsultarPlanillaSemanal
    @inIdEmpleado INT
  ,@inIdSemanaPlanilla INT = NULL
  ,@inFechaInicio DATE = NULL
  ,@inFechaFin DATE = NULL
  ,@outResultCode INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @outResultCode = 0;

    BEGIN TRY
        SELECT
            pse.IdPlanillaSemXEmpleado
          , sp.IdSemanaPlanilla
          , sp.FechaInicio
          , sp.FechaFin
          , sp.Cerrada
          , e.IdEmpleado
          , e.Nombre AS NombreEmpleado
          , e.ValorDocumentoIdentidad
          , p.Nombre AS NombrePuesto
          , p.SalarioXHora
          , pse.HorasOrdinarias
          , pse.HorasExtraNormales
          , pse.HorasExtraDobles
          , pse.SalarioBruto
          , pse.TotalDeducciones
          , pse.SalarioNeto
        FROM dbo.PlanillaSemXEmpleado AS pse
        INNER JOIN dbo.SemanaPlanilla AS sp
            ON (sp.IdSemanaPlanilla = pse.IdSemanaPlanilla)
        INNER JOIN dbo.Empleado AS e
            ON (e.IdEmpleado = pse.IdEmpleado)
        INNER JOIN dbo.Puesto AS p
            ON (p.IdPuesto = e.IdPuesto)
        WHERE (pse.IdEmpleado = @inIdEmpleado)
          AND (@inIdSemanaPlanilla IS NULL OR sp.IdSemanaPlanilla = @inIdSemanaPlanilla)
          AND (@inFechaInicio IS NULL OR sp.FechaInicio >= @inFechaInicio)
          AND (@inFechaFin IS NULL OR sp.FechaFin <= @inFechaFin)
        ORDER BY
            sp.FechaInicio DESC;

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
            'sp_ConsultarPlanillaSemanal'
          , ERROR_MESSAGE()
          , ERROR_SEVERITY()
          , ERROR_STATE()
          , ERROR_LINE()
        );

    END CATCH;
END;
GO

CREATE PROCEDURE dbo.sp_ConsultarDetalleDeduccionesSemana
    @inIdEmpleado INT
  ,@inIdSemanaPlanilla INT = NULL
  ,@inFechaInicio DATE = NULL
  ,@inFechaFin DATE = NULL
  ,@outResultCode INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @outResultCode = 0;

    BEGIN TRY
        SELECT
            sp.IdSemanaPlanilla
          , sp.FechaInicio
          , sp.FechaFin
          , pse.IdPlanillaSemXEmpleado
          , td.IdTipoDeduccion
          , td.Nombre AS NombreDeduccion
          , td.EsObligatoria
          , td.EsPorcentual
          , tm.IdTipoMovimiento
          , tm.Nombre AS NombreMovimiento
          , COUNT(mp.IdMovimientoPlanilla) AS CantidadMovimientos
          , SUM(mp.Monto) AS MontoTotal
        FROM dbo.PlanillaSemXEmpleado AS pse
        INNER JOIN dbo.SemanaPlanilla AS sp
            ON (sp.IdSemanaPlanilla = pse.IdSemanaPlanilla)
        INNER JOIN dbo.MovimientoPlanilla AS mp
            ON (mp.IdPlanillaSemXEmpleado = pse.IdPlanillaSemXEmpleado)
        INNER JOIN dbo.TipoMovimiento AS tm
            ON (tm.IdTipoMovimiento = mp.IdTipoMovimiento)
        INNER JOIN dbo.TipoDeduccion AS td
            ON (td.IdTipoMovimiento = tm.IdTipoMovimiento)
        WHERE (pse.IdEmpleado = @inIdEmpleado)
          AND (tm.Accion = '-')
          AND (@inIdSemanaPlanilla IS NULL OR sp.IdSemanaPlanilla = @inIdSemanaPlanilla)
          AND (@inFechaInicio IS NULL OR sp.FechaInicio >= @inFechaInicio)
          AND (@inFechaFin IS NULL OR sp.FechaFin <= @inFechaFin)
        GROUP BY
            sp.IdSemanaPlanilla
          , sp.FechaInicio
          , sp.FechaFin
          , pse.IdPlanillaSemXEmpleado
          , td.IdTipoDeduccion
          , td.Nombre
          , td.EsObligatoria
          , td.EsPorcentual
          , tm.IdTipoMovimiento
          , tm.Nombre
        ORDER BY
            sp.FechaInicio DESC
          , td.Nombre;

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
            'sp_ConsultarDetalleDeduccionesSemana'
          , ERROR_MESSAGE()
          , ERROR_SEVERITY()
          , ERROR_STATE()
          , ERROR_LINE()
        );

    END CATCH;
END;
GO

CREATE PROCEDURE dbo.sp_ConsultarDetalleHorasSemana
    @inIdEmpleado INT
  ,@inIdSemanaPlanilla INT = NULL
  ,@inFechaInicio DATE = NULL
  ,@inFechaFin DATE = NULL
  ,@outResultCode INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @outResultCode = 0;

    BEGIN TRY
        SELECT
            sp.IdSemanaPlanilla
          , sp.FechaInicio AS FechaInicioSemana
          , sp.FechaFin AS FechaFinSemana
          , ma.IdMarcaAsistencia
          , ma.FechaOperacion
          , ma.FechaHoraEntrada
          , ma.FechaHoraSalida
          , SUM(CASE WHEN tm.IdTipoMovimiento = 1 THEN mp.Cantidad ELSE 0 END) AS HorasOrdinarias
          , SUM(CASE WHEN tm.IdTipoMovimiento = 2 THEN mp.Cantidad ELSE 0 END) AS HorasExtraNormales
          , SUM(CASE WHEN tm.IdTipoMovimiento = 3 THEN mp.Cantidad ELSE 0 END) AS HorasExtraDobles
          , SUM(CASE WHEN tm.IdTipoMovimiento IN (1, 2, 3) THEN mp.Monto ELSE 0 END) AS MontoGenerado
        FROM dbo.PlanillaSemXEmpleado AS pse
        INNER JOIN dbo.SemanaPlanilla AS sp
            ON (sp.IdSemanaPlanilla = pse.IdSemanaPlanilla)
        INNER JOIN dbo.MovimientoPlanilla AS mp
            ON (mp.IdPlanillaSemXEmpleado = pse.IdPlanillaSemXEmpleado)
        INNER JOIN dbo.TipoMovimiento AS tm
            ON (tm.IdTipoMovimiento = mp.IdTipoMovimiento)
        INNER JOIN dbo.MarcaAsistencia AS ma
            ON (ma.IdMarcaAsistencia = mp.IdMarcaAsistencia)
        WHERE (pse.IdEmpleado = @inIdEmpleado)
          AND (tm.IdTipoMovimiento IN (1, 2, 3))
          AND (@inIdSemanaPlanilla IS NULL OR sp.IdSemanaPlanilla = @inIdSemanaPlanilla)
          AND (@inFechaInicio IS NULL OR sp.FechaInicio >= @inFechaInicio)
          AND (@inFechaFin IS NULL OR sp.FechaFin <= @inFechaFin)
        GROUP BY
            sp.IdSemanaPlanilla
          , sp.FechaInicio
          , sp.FechaFin
          , ma.IdMarcaAsistencia
          , ma.FechaOperacion
          , ma.FechaHoraEntrada
          , ma.FechaHoraSalida
        ORDER BY
            ma.FechaOperacion
          , ma.FechaHoraEntrada;

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
            'sp_ConsultarDetalleHorasSemana'
          , ERROR_MESSAGE()
          , ERROR_SEVERITY()
          , ERROR_STATE()
          , ERROR_LINE()
        );

    END CATCH;
END;
GO

CREATE PROCEDURE dbo.sp_ConsultarPlanillaMensual
    @inIdEmpleado INT
  ,@inIdMesPlanilla INT = NULL
  ,@inFechaInicio DATE = NULL
  ,@inFechaFin DATE = NULL
  ,@outResultCode INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @outResultCode = 0;

    BEGIN TRY
        SELECT
            pme.IdPlanillaMesXEmpleado
          , mp.IdMesPlanilla
          , mp.FechaInicio
          , mp.FechaFin
          , mp.CantidadJueves
          , mp.Cerrado
          , e.IdEmpleado
          , e.Nombre AS NombreEmpleado
          , e.ValorDocumentoIdentidad
          , p.Nombre AS NombrePuesto
          , pme.SalarioBrutoMensual
          , pme.TotalDeduccionesMensual
          , pme.SalarioNetoMensual
        FROM dbo.PlanillaMesXEmpleado AS pme
        INNER JOIN dbo.MesPlanilla AS mp
            ON (mp.IdMesPlanilla = pme.IdMesPlanilla)
        INNER JOIN dbo.Empleado AS e
            ON (e.IdEmpleado = pme.IdEmpleado)
        INNER JOIN dbo.Puesto AS p
            ON (p.IdPuesto = e.IdPuesto)
        WHERE (pme.IdEmpleado = @inIdEmpleado)
          AND (@inIdMesPlanilla IS NULL OR mp.IdMesPlanilla = @inIdMesPlanilla)
          AND (@inFechaInicio IS NULL OR mp.FechaInicio >= @inFechaInicio)
          AND (@inFechaFin IS NULL OR mp.FechaFin <= @inFechaFin)
        ORDER BY
            mp.FechaInicio DESC;

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
            'sp_ConsultarPlanillaMensual'
          , ERROR_MESSAGE()
          , ERROR_SEVERITY()
          , ERROR_STATE()
          , ERROR_LINE()
        );

    END CATCH;
END;
GO

CREATE PROCEDURE dbo.sp_ConsultarDetalleDeduccionesMes
    @inIdEmpleado INT
  ,@inIdMesPlanilla INT = NULL
  ,@inFechaInicio DATE = NULL
  ,@inFechaFin DATE = NULL
  ,@outResultCode INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @outResultCode = 0;

    BEGIN TRY
        SELECT
            mp.IdMesPlanilla
          , mp.FechaInicio
          , mp.FechaFin
          , pme.IdPlanillaMesXEmpleado
          , td.IdTipoDeduccion
          , td.Nombre AS NombreDeduccion
          , td.EsObligatoria
          , td.EsPorcentual
          , dxm.MontoTotal
        FROM dbo.PlanillaMesXEmpleado AS pme
        INNER JOIN dbo.MesPlanilla AS mp
            ON (mp.IdMesPlanilla = pme.IdMesPlanilla)
        INNER JOIN dbo.DeduccionXEmpleadoXMes AS dxm
            ON (dxm.IdPlanillaMesXEmpleado = pme.IdPlanillaMesXEmpleado)
        INNER JOIN dbo.TipoDeduccion AS td
            ON (td.IdTipoDeduccion = dxm.IdTipoDeduccion)
        WHERE (pme.IdEmpleado = @inIdEmpleado)
          AND (@inIdMesPlanilla IS NULL OR mp.IdMesPlanilla = @inIdMesPlanilla)
          AND (@inFechaInicio IS NULL OR mp.FechaInicio >= @inFechaInicio)
          AND (@inFechaFin IS NULL OR mp.FechaFin <= @inFechaFin)
        ORDER BY
            mp.FechaInicio DESC
          , td.Nombre;

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
            'sp_ConsultarDetalleDeduccionesMes'
          , ERROR_MESSAGE()
          , ERROR_SEVERITY()
          , ERROR_STATE()
          , ERROR_LINE()
        );

    END CATCH;
END;
GO

CREATE PROCEDURE dbo.sp_WebLogin
    @inUsername VARCHAR(50)
  ,@inPassword VARCHAR(255)
  ,@inIPOrigen VARCHAR(45) = '127.0.0.1'
  ,@outResultCode INT = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @vIdUsuario INT;
    DECLARE @vTipoUsuario TINYINT;

    EXEC dbo.sp_Login
        @inUsername = @inUsername
      ,@inPassword = @inPassword
      ,@inIPOrigen = @inIPOrigen
      ,@outIdUsuario = @vIdUsuario OUTPUT
      ,@outTipoUsuario = @vTipoUsuario OUTPUT
      ,@outResultCode = @outResultCode OUTPUT;

    SELECT
        @outResultCode AS ResultCode
      ,@vIdUsuario AS IdUsuario
      ,@vTipoUsuario AS TipoUsuario;
END;
GO

CREATE PROCEDURE dbo.sp_WebListarEmpleadosConFiltro
    @inNombre VARCHAR(150) = NULL
  ,@inValorDocumento VARCHAR(30) = NULL
  ,@inSoloActivos BIT = 1
  ,@inIdUsuarioConsulta INT = NULL
  ,@inIPOrigen VARCHAR(45) = '127.0.0.1'
  ,@outResultCode INT = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    EXEC dbo.sp_ListarEmpleadosConFiltro
        @inNombre = @inNombre
      ,@inValorDocumento = @inValorDocumento
      ,@inSoloActivos = @inSoloActivos
      ,@inIdUsuarioConsulta = @inIdUsuarioConsulta
      ,@inIPOrigen = @inIPOrigen
      ,@outResultCode = @outResultCode OUTPUT;

    SELECT @outResultCode AS ResultCode;
END;
GO

CREATE PROCEDURE dbo.sp_WebObtenerEmpleado
    @inIdEmpleado INT = NULL
  ,@inValorDocumento VARCHAR(30) = NULL
  ,@outResultCode INT = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    EXEC dbo.sp_ObtenerEmpleado
        @inIdEmpleado = @inIdEmpleado
      ,@inValorDocumento = @inValorDocumento
      ,@outResultCode = @outResultCode OUTPUT;

    SELECT @outResultCode AS ResultCode;
END;
GO

CREATE PROCEDURE dbo.sp_WebObtenerEmpleadoPorUsuario
    @inIdUsuario INT
  ,@outResultCode INT = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @outResultCode = 0;

    BEGIN TRY
        SELECT
            e.IdEmpleado
          , e.Nombre
          , e.ValorDocumentoIdentidad
          , e.IdUsuario
        FROM dbo.Empleado AS e
        WHERE (e.IdUsuario = @inIdUsuario)
          AND (e.Activo = 1);

        SELECT @outResultCode AS ResultCode;

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
            'sp_WebObtenerEmpleadoPorUsuario'
          , ERROR_MESSAGE()
          , ERROR_SEVERITY()
          , ERROR_STATE()
          , ERROR_LINE()
        );

        SELECT @outResultCode AS ResultCode;

    END CATCH;
END;
GO

CREATE PROCEDURE dbo.sp_WebListarPuestos
    @outResultCode INT = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @outResultCode = 0;

    BEGIN TRY
        SELECT
            p.IdPuesto
          , p.Nombre
          , p.SalarioXHora
        FROM dbo.Puesto AS p
        ORDER BY
            p.Nombre;

        SELECT @outResultCode AS ResultCode;

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
            'sp_WebListarPuestos'
          , ERROR_MESSAGE()
          , ERROR_SEVERITY()
          , ERROR_STATE()
          , ERROR_LINE()
        );

        SELECT @outResultCode AS ResultCode;

    END CATCH;
END;
GO

CREATE PROCEDURE dbo.sp_WebInsertarEmpleado
    @inNombre VARCHAR(150)
  ,@inValorDocumento VARCHAR(30)
  ,@inNombrePuesto VARCHAR(100)
  ,@inUsername VARCHAR(50)
  ,@inPassword VARCHAR(255)
  ,@inCuentaBancaria VARCHAR(30)
  ,@inFechaIngreso DATE
  ,@inIdUsuarioAdmin INT
  ,@inIPOrigen VARCHAR(45) = '127.0.0.1'
  ,@outResultCode INT = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @vIdEmpleadoNuevo INT;

    EXEC dbo.sp_InsertarEmpleado
        @inNombre = @inNombre
      ,@inValorDocumento = @inValorDocumento
      ,@inNombrePuesto = @inNombrePuesto
      ,@inUsername = @inUsername
      ,@inPassword = @inPassword
      ,@inCuentaBancaria = @inCuentaBancaria
      ,@inFechaIngreso = @inFechaIngreso
      ,@inIdUsuarioAdmin = @inIdUsuarioAdmin
      ,@inIPOrigen = @inIPOrigen
      ,@outIdEmpleadoNuevo = @vIdEmpleadoNuevo OUTPUT
      ,@outResultCode = @outResultCode OUTPUT;

    SELECT
        @outResultCode AS ResultCode
      ,@vIdEmpleadoNuevo AS IdEmpleadoNuevo;
END;
GO

CREATE PROCEDURE dbo.sp_WebActualizarEmpleado
    @inIdEmpleado INT
  ,@inNombre VARCHAR(150)
  ,@inValorDocumento VARCHAR(30)
  ,@inNombrePuesto VARCHAR(100)
  ,@inUsername VARCHAR(50)
  ,@inPassword VARCHAR(255) = NULL
  ,@inCuentaBancaria VARCHAR(30) = NULL
  ,@inFechaIngreso DATE
  ,@inActivo BIT = 1
  ,@inIdUsuarioAdmin INT
  ,@inIPOrigen VARCHAR(45) = '127.0.0.1'
  ,@outResultCode INT = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    EXEC dbo.sp_ActualizarEmpleado
        @inIdEmpleado = @inIdEmpleado
      ,@inNombre = @inNombre
      ,@inValorDocumento = @inValorDocumento
      ,@inNombrePuesto = @inNombrePuesto
      ,@inUsername = @inUsername
      ,@inPassword = @inPassword
      ,@inCuentaBancaria = @inCuentaBancaria
      ,@inFechaIngreso = @inFechaIngreso
      ,@inActivo = @inActivo
      ,@inIdUsuarioAdmin = @inIdUsuarioAdmin
      ,@inIPOrigen = @inIPOrigen
      ,@outResultCode = @outResultCode OUTPUT;

    SELECT @outResultCode AS ResultCode;
END;
GO

CREATE PROCEDURE dbo.sp_WebEliminarEmpleado
    @inValorDocumento VARCHAR(30)
  ,@inIdUsuarioAdmin INT
  ,@inIPOrigen VARCHAR(45) = '127.0.0.1'
  ,@outResultCode INT = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    EXEC dbo.sp_EliminarEmpleado
        @inValorDocumento = @inValorDocumento
      ,@inIdUsuarioAdmin = @inIdUsuarioAdmin
      ,@inIPOrigen = @inIPOrigen
      ,@outResultCode = @outResultCode OUTPUT;

    SELECT @outResultCode AS ResultCode;
END;
GO

CREATE PROCEDURE dbo.sp_WebRegistrarEventoBitacora
    @inIdUsuario INT
  ,@inIdTipoEvento INT
  ,@inIPOrigen VARCHAR(45)
  ,@inParametros NVARCHAR(MAX) = NULL
  ,@inDatosAntes NVARCHAR(MAX) = NULL
  ,@inDatosDespues NVARCHAR(MAX) = NULL
  ,@outResultCode INT = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @outResultCode = 0;

    BEGIN TRY
        INSERT INTO dbo.BitacoraEvento (
            IdUsuario
          , IdTipoEvento
          , IPOrigen
          , Parametros
          , DatosAntes
          , DatosDespues
        )
        VALUES (
            @inIdUsuario
          ,@inIdTipoEvento
          ,@inIPOrigen
          ,@inParametros
          ,@inDatosAntes
          ,@inDatosDespues
        );

        SELECT @outResultCode AS ResultCode;

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
            'sp_WebRegistrarEventoBitacora'
          , ERROR_MESSAGE()
          , ERROR_SEVERITY()
          , ERROR_STATE()
          , ERROR_LINE()
        );

        SELECT @outResultCode AS ResultCode;

    END CATCH;
END;
GO

CREATE PROCEDURE dbo.sp_WebConsultarPlanillaSemanal
    @inIdEmpleado INT
  ,@inIdSemanaPlanilla INT = NULL
  ,@outResultCode INT = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    EXEC dbo.sp_ConsultarPlanillaSemanal
        @inIdEmpleado = @inIdEmpleado
      ,@inIdSemanaPlanilla = @inIdSemanaPlanilla
      ,@outResultCode = @outResultCode OUTPUT;

    SELECT @outResultCode AS ResultCode;
END;
GO

CREATE PROCEDURE dbo.sp_WebConsultarDetalleDeduccionesSemana
    @inIdEmpleado INT
  ,@inIdSemanaPlanilla INT = NULL
  ,@outResultCode INT = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    EXEC dbo.sp_ConsultarDetalleDeduccionesSemana
        @inIdEmpleado = @inIdEmpleado
      ,@inIdSemanaPlanilla = @inIdSemanaPlanilla
      ,@outResultCode = @outResultCode OUTPUT;

    SELECT @outResultCode AS ResultCode;
END;
GO

CREATE PROCEDURE dbo.sp_WebConsultarDetalleHorasSemana
    @inIdEmpleado INT
  ,@inIdSemanaPlanilla INT = NULL
  ,@outResultCode INT = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    EXEC dbo.sp_ConsultarDetalleHorasSemana
        @inIdEmpleado = @inIdEmpleado
      ,@inIdSemanaPlanilla = @inIdSemanaPlanilla
      ,@outResultCode = @outResultCode OUTPUT;

    SELECT @outResultCode AS ResultCode;
END;
GO

CREATE PROCEDURE dbo.sp_WebConsultarPlanillaMensual
    @inIdEmpleado INT
  ,@inIdMesPlanilla INT = NULL
  ,@outResultCode INT = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    EXEC dbo.sp_ConsultarPlanillaMensual
        @inIdEmpleado = @inIdEmpleado
      ,@inIdMesPlanilla = @inIdMesPlanilla
      ,@outResultCode = @outResultCode OUTPUT;

    SELECT @outResultCode AS ResultCode;
END;
GO

CREATE PROCEDURE dbo.sp_WebConsultarDetalleDeduccionesMes
    @inIdEmpleado INT
  ,@inIdMesPlanilla INT = NULL
  ,@outResultCode INT = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    EXEC dbo.sp_ConsultarDetalleDeduccionesMes
        @inIdEmpleado = @inIdEmpleado
      ,@inIdMesPlanilla = @inIdMesPlanilla
      ,@outResultCode = @outResultCode OUTPUT;

    SELECT @outResultCode AS ResultCode;
END;
GO

PRINT 'SPs de consultas creados exitosamente.';
GO
