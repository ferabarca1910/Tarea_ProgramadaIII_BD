
-- semana y mes, y SP maestro que ejecuta toda la simulacion



USE PlanillaObrera;
GO

--Determina si una fecha es domingo o feriado
--Usada para calcular si las horas extra son normales o dobles

IF OBJECT_ID('dbo.fn_EsFeriadoODomingo', 'FN') IS NOT NULL
    DROP FUNCTION dbo.fn_EsFeriadoODomingo;
GO

CREATE FUNCTION dbo.fn_EsFeriadoODomingo(@inFecha DATE)
RETURNS BIT
AS
BEGIN

    DECLARE @vEsFeriadoODomingo BIT = 0;

    IF (DATEPART(WEEKDAY, @inFecha) = 1)
        SET @vEsFeriadoODomingo = 1;

    IF EXISTS (
        SELECT 1
        FROM dbo.Feriado AS f
        WHERE (f.Fecha = @inFecha)
    )
        SET @vEsFeriadoODomingo = 1;

    RETURN @vEsFeriadoODomingo;

END;
GO

--Calcula el ultimo jueves de un mes dado
--Usada para determinar el cierre mensual de la planilla

IF OBJECT_ID('dbo.fn_UltimoJuevesDelMes', 'FN') IS NOT NULL
    DROP FUNCTION dbo.fn_UltimoJuevesDelMes;
GO

CREATE FUNCTION dbo.fn_UltimoJuevesDelMes(@inAnio INT, @inMes INT)
RETURNS DATE
AS
BEGIN

    DECLARE @vUltimoDia DATE;
    DECLARE @vDia       DATE;

    SET @vUltimoDia = EOMONTH(
        CAST(CAST(@inAnio AS VARCHAR(4)) + '-' + RIGHT('0' + CAST(@inMes AS VARCHAR(2)), 2) + '-01' AS DATE)
    );
    SET @vDia = @vUltimoDia;

    WHILE (DATEPART(WEEKDAY, @vDia) <> 5)
        SET @vDia = DATEADD(DAY, -1, @vDia);

    RETURN @vDia;

END;
GO

--Cuenta cuantos jueves hay entre dos fechas
--Determina si un mes planilla tiene 4 o 5 semanas

IF OBJECT_ID('dbo.fn_ContarJueves', 'FN') IS NOT NULL
    DROP FUNCTION dbo.fn_ContarJueves;
GO

CREATE FUNCTION dbo.fn_ContarJueves(@inFechaInicio DATE, @inFechaFin DATE)
RETURNS TINYINT
AS
BEGIN

    DECLARE @vCantidad TINYINT = 0;

    ;WITH Fechas AS (
        SELECT @inFechaInicio AS Fecha
        UNION ALL
        SELECT DATEADD(DAY, 1, Fecha)
        FROM Fechas
        WHERE (Fecha < @inFechaFin)
    )
    SELECT @vCantidad = COUNT(*)
    FROM Fechas
    WHERE (DATEPART(WEEKDAY, Fecha) = 5)
    OPTION (MAXRECURSION 60);

    RETURN @vCantidad;

END;
GO


--SP: Inicializa el sistema antes de correr la simulacion

IF OBJECT_ID('dbo.sp_InicializarSistema', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_InicializarSistema;
GO

CREATE PROCEDURE dbo.sp_InicializarSistema
    @inFechaInicioSimulacion   DATE
  , @outResultCode             INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @outResultCode = 0;

    DECLARE @vFechaFinMes  DATE;
    DECLARE @vMesInicio    INT;
    DECLARE @vAnioInicio   INT;
    DECLARE @vNumJueves    TINYINT;
    DECLARE @vIdMes        INT;
    DECLARE @vFechaFinSem  DATE;

    SET @vMesInicio  = MONTH(@inFechaInicioSimulacion);
    SET @vAnioInicio = YEAR(@inFechaInicioSimulacion);
    SET @vFechaFinMes = dbo.fn_UltimoJuevesDelMes(@vAnioInicio, @vMesInicio);
    SET @vNumJueves   = dbo.fn_ContarJueves(@inFechaInicioSimulacion, @vFechaFinMes);
    SET @vFechaFinSem = DATEADD(DAY, 6, @inFechaInicioSimulacion);

    BEGIN TRY

        INSERT INTO dbo.MesPlanilla (
            FechaInicio
          , FechaFin
          , CantidadJueves
          , Cerrado
        )
        VALUES (
            @inFechaInicioSimulacion
          , @vFechaFinMes
          , @vNumJueves
          , 0
        );

        SET @vIdMes = SCOPE_IDENTITY();

        INSERT INTO dbo.SemanaPlanilla (
            IdMesPlanilla
          , FechaInicio
          , FechaFin
          , Cerrada
        )
        VALUES (
            @vIdMes
          , @inFechaInicioSimulacion
          , @vFechaFinSem
          , 0
        );

        PRINT 'Sistema inicializado. Primera semana: '
            + CONVERT(VARCHAR, @inFechaInicioSimulacion, 103) + ' - '
            + CONVERT(VARCHAR, @vFechaFinSem, 103);

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
            'sp_InicializarSistema'
          , ERROR_MESSAGE()
          , ERROR_SEVERITY()
          , ERROR_STATE()
          , ERROR_LINE()
        );

    END CATCH

END;
GO

--Procesa una marca de asistencia individual
--Calcula horas ordinarias, extra normales y extra dobles
--Inserta los movimientos correspondientes y actualiza
--el acumulado semanal del empleado, todo en una transaccion

IF OBJECT_ID('dbo.sp_ProcesarAsistencia', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_ProcesarAsistencia;
GO

CREATE PROCEDURE dbo.sp_ProcesarAsistencia
    @inValorDocumento       VARCHAR(30)
  , @inFechaHoraEntrada     DATETIME
  , @inFechaHoraSalida      DATETIME
  , @inIdUsuarioSistema     INT
  , @inIPOrigen             VARCHAR(45) = '127.0.0.1'
  , @outResultCode          INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @outResultCode = 0;

    --declaraciones y calculos antes de abrir transaccion

    DECLARE @vIdEmpleado            INT;
    DECLARE @vSalarioXHora           DECIMAL(10,2);
    DECLARE @vFechaEntrada           DATE;
    DECLARE @vIdTipoJornada          INT;
    DECLARE @vIdPlanillaSemXEmpleado INT;
    DECLARE @vFinJornadaDT           DATETIME;
    DECLARE @vMinutosTrabajados      INT;
    DECLARE @vMinutosJornada         INT;
    DECLARE @vMinutosOrdinarios      INT;
    DECLARE @vHorasOrdinarias        INT;
    DECLARE @vMinutosExtra           INT;
    DECLARE @vFechaExtra             DATE;
    DECLARE @vEsFerODom              BIT;
    DECLARE @vHorasExtraNormales     INT = 0;
    DECLARE @vHorasExtraDobles       INT = 0;
    DECLARE @vMinHastaMedNoche       INT;
    DECLARE @vEsSigDiaFerODom        BIT;
    DECLARE @vMinExtraEnSigDia       INT;
    DECLARE @vMontoOrdinario         DECIMAL(12,2);
    DECLARE @vMontoExtraNormal       DECIMAL(12,2);
    DECLARE @vMontoExtraDoble        DECIMAL(12,2);
    DECLARE @vIdMarca                INT;
    DECLARE @vParams                 NVARCHAR(500);

    SET @vFechaEntrada = CAST(@inFechaHoraEntrada AS DATE);

    SELECT
        @vIdEmpleado   = e.IdEmpleado
      , @vSalarioXHora = p.SalarioXHora
    FROM dbo.Empleado AS e
    INNER JOIN dbo.Puesto AS p
        ON (p.IdPuesto = e.IdPuesto)
    WHERE (e.ValorDocumentoIdentidad = @inValorDocumento)
      AND (e.Activo = 1);

    IF (@vIdEmpleado IS NULL)
    BEGIN
        SET @outResultCode = 50012;
        RETURN;
    END;

    SELECT TOP (1)
        @vIdTipoJornada = jes.IdTipoJornada
    FROM dbo.JornadaEmpleadoSemana AS jes
    WHERE (jes.IdEmpleado = @vIdEmpleado)
      AND (jes.FechaInicioSemana <= @vFechaEntrada)
    ORDER BY jes.FechaInicioSemana DESC;

    IF (@vIdTipoJornada IS NULL)
    BEGIN
        SET @outResultCode = 50013;
        RETURN;
    END;

    SELECT
        @vFinJornadaDT =
            CASE
                WHEN (tj.HoraFin <= tj.HoraInicio)
                    THEN CAST(DATEADD(DAY, 1, @vFechaEntrada) AS DATETIME)
                         + CAST(tj.HoraFin AS DATETIME) - CAST('00:00:00' AS DATETIME)
                ELSE
                    CAST(@vFechaEntrada AS DATETIME)
                    + CAST(tj.HoraFin AS DATETIME) - CAST('00:00:00' AS DATETIME)
            END
    FROM dbo.TipoJornada AS tj
    WHERE (tj.IdTipoJornada = @vIdTipoJornada);

    SELECT TOP (1)
        @vIdPlanillaSemXEmpleado = pse.IdPlanillaSemXEmpleado
    FROM dbo.PlanillaSemXEmpleado AS pse
    INNER JOIN dbo.SemanaPlanilla AS sp
        ON (sp.IdSemanaPlanilla = pse.IdSemanaPlanilla)
    WHERE (pse.IdEmpleado = @vIdEmpleado)
      AND (sp.Cerrada = 0)
      AND (sp.FechaInicio <= @vFechaEntrada)
      AND (sp.FechaFin >= @vFechaEntrada);

    IF (@vIdPlanillaSemXEmpleado IS NULL)
    BEGIN
        SET @outResultCode = 50014;
        RETURN;
    END;

    --Calculo de minutos trabajados vs minutos de jornada
    SET @vMinutosTrabajados = DATEDIFF(MINUTE, @inFechaHoraEntrada, @inFechaHoraSalida);
    SET @vMinutosJornada    = DATEDIFF(MINUTE, @inFechaHoraEntrada, @vFinJornadaDT);

    IF (@vMinutosJornada < 0)
        SET @vMinutosJornada = 0;

    SET @vMinutosOrdinarios = CASE
        WHEN (@vMinutosTrabajados <= @vMinutosJornada) THEN @vMinutosTrabajados
        ELSE @vMinutosJornada
    END;
    SET @vHorasOrdinarias = @vMinutosOrdinarios / 60;

    SET @vMinutosExtra = CASE
        WHEN (@vMinutosTrabajados > @vMinutosJornada) THEN (@vMinutosTrabajados - @vMinutosJornada)
        ELSE 0
    END;

    SET @vFechaExtra = CAST(@vFinJornadaDT AS DATE);
    SET @vEsFerODom  = dbo.fn_EsFeriadoODomingo(@vFechaExtra);

    IF (@vMinutosExtra > 0)
    BEGIN

        IF (@vEsFerODom = 0)
        BEGIN

            SET @vMinHastaMedNoche = DATEDIFF(
                MINUTE
              , @vFinJornadaDT
              , CAST(DATEADD(DAY, 1, CAST(@vFinJornadaDT AS DATE)) AS DATETIME)
            );

            IF (@vMinutosExtra <= @vMinHastaMedNoche)
            BEGIN
                SET @vHorasExtraNormales = @vMinutosExtra / 60;
            END
            ELSE
            BEGIN
                SET @vEsSigDiaFerODom  = dbo.fn_EsFeriadoODomingo(DATEADD(DAY, 1, @vFechaExtra));
                SET @vHorasExtraNormales = @vMinHastaMedNoche / 60;
                SET @vMinExtraEnSigDia  = @vMinutosExtra - @vMinHastaMedNoche;

                IF (@vEsSigDiaFerODom = 1)
                    SET @vHorasExtraDobles = @vMinExtraEnSigDia / 60;
                ELSE
                    SET @vHorasExtraNormales = @vHorasExtraNormales + (@vMinExtraEnSigDia / 60);
            END;

        END
        ELSE
        BEGIN
            SET @vHorasExtraDobles = @vMinutosExtra / 60;
        END;

    END;

    SET @vMontoOrdinario   = @vHorasOrdinarias    * @vSalarioXHora;
    SET @vMontoExtraNormal = @vHorasExtraNormales * @vSalarioXHora * 1.5;
    SET @vMontoExtraDoble  = @vHorasExtraDobles   * @vSalarioXHora * 2.0;

    --Transaccion al final: solo INSERTs/UPDATEs

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO dbo.MarcaAsistencia (
            IdEmpleado
          , FechaHoraEntrada
          , FechaHoraSalida
          , FechaOperacion
        )
        VALUES (
            @vIdEmpleado
          , @inFechaHoraEntrada
          , @inFechaHoraSalida
          , @vFechaEntrada
        );

        SET @vIdMarca = SCOPE_IDENTITY();

        IF (@vHorasOrdinarias > 0)
            INSERT INTO dbo.MovimientoPlanilla (
                IdPlanillaSemXEmpleado
              , IdTipoMovimiento
              , IdMarcaAsistencia
              , Fecha
              , Cantidad
              , Monto
            )
            VALUES (
                @vIdPlanillaSemXEmpleado
              , 1
              , @vIdMarca
              , @vFechaEntrada
              , @vHorasOrdinarias
              , @vMontoOrdinario
            );

        IF (@vHorasExtraNormales > 0)
            INSERT INTO dbo.MovimientoPlanilla (
                IdPlanillaSemXEmpleado
              , IdTipoMovimiento
              , IdMarcaAsistencia
              , Fecha
              , Cantidad
              , Monto
            )
            VALUES (
                @vIdPlanillaSemXEmpleado
              , 2
              , @vIdMarca
              , @vFechaEntrada
              , @vHorasExtraNormales
              , @vMontoExtraNormal
            );

        IF (@vHorasExtraDobles > 0)
            INSERT INTO dbo.MovimientoPlanilla (
                IdPlanillaSemXEmpleado
              , IdTipoMovimiento
              , IdMarcaAsistencia
              , Fecha
              , Cantidad
              , Monto
            )
            VALUES (
                @vIdPlanillaSemXEmpleado
              , 3
              , @vIdMarca
              , @vFechaEntrada
              , @vHorasExtraDobles
              , @vMontoExtraDoble
            );

        UPDATE dbo.PlanillaSemXEmpleado
        SET
            SalarioBruto       = SalarioBruto       + @vMontoOrdinario + @vMontoExtraNormal + @vMontoExtraDoble
          , HorasOrdinarias    = HorasOrdinarias    + @vHorasOrdinarias
          , HorasExtraNormales = HorasExtraNormales + @vHorasExtraNormales
          , HorasExtraDobles   = HorasExtraDobles   + @vHorasExtraDobles
        WHERE (IdPlanillaSemXEmpleado = @vIdPlanillaSemXEmpleado);

        SET @vParams =
            N'{"empleado_doc":"' + @inValorDocumento
            + N'","entrada":"' + CONVERT(VARCHAR, @inFechaHoraEntrada, 120)
            + N'","salida":"'  + CONVERT(VARCHAR, @inFechaHoraSalida, 120) + N'"}';

        INSERT INTO dbo.BitacoraEvento (
            IdUsuario
          , IdTipoEvento
          , IPOrigen
          , Parametros
        )
        VALUES (
            @inIdUsuarioSistema
          , 14
          , @inIPOrigen
          , @vParams
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
            'sp_ProcesarAsistencia'
          , ERROR_MESSAGE()
          , ERROR_SEVERITY()
          , ERROR_STATE()
          , ERROR_LINE()
        );

    END CATCH

END;
GO


--SP: Cierre semanal de planilla (se ejecuta los jueves)

IF OBJECT_ID('dbo.sp_CierreSemanal', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_CierreSemanal;
GO

CREATE PROCEDURE dbo.sp_CierreSemanal
    @inFechaJueves      DATE
  , @inIdUsuarioSistema INT
  , @inIPOrigen         VARCHAR(45) = '127.0.0.1'
  , @outResultCode      INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @outResultCode = 0;

    --Pre-proceso: identificar la semana y el mes

    DECLARE @vIdSemanaPlanilla INT;
    DECLARE @vIdMesPlanilla    INT;
    DECLARE @vCantidadJueves   TINYINT;

    SELECT
        @vIdSemanaPlanilla = sp.IdSemanaPlanilla
      , @vIdMesPlanilla    = sp.IdMesPlanilla
    FROM dbo.SemanaPlanilla AS sp
    WHERE (sp.FechaFin = @inFechaJueves)
      AND (sp.Cerrada = 0);

    IF (@vIdSemanaPlanilla IS NULL)
    BEGIN
        SET @outResultCode = 50015;
        RETURN;
    END;

    SELECT
        @vCantidadJueves = mp.CantidadJueves
    FROM dbo.MesPlanilla AS mp
    WHERE (mp.IdMesPlanilla = @vIdMesPlanilla);

    --Tabla variable con las deducciones porcentuales a aplicar por empleado
    DECLARE @tDeduccionesPct TABLE (
        IdPlanillaSemXEmpleado   INT
      , IdPlanillaMesXEmpleado   INT
      , IdTipoDeduccion          INT
      , Monto                    DECIMAL(12,2)
    );

    INSERT INTO @tDeduccionesPct (
        IdPlanillaSemXEmpleado
      , IdPlanillaMesXEmpleado
      , IdTipoDeduccion
      , Monto
    )
    SELECT
        pse.IdPlanillaSemXEmpleado
      , pme.IdPlanillaMesXEmpleado
      , de.IdTipoDeduccion
      , ROUND(pse.SalarioBruto * td.Valor, 2)
    FROM dbo.PlanillaSemXEmpleado AS pse
    INNER JOIN dbo.DeduccionEmpleado AS de
        ON (de.IdEmpleado = pse.IdEmpleado)
    INNER JOIN dbo.TipoDeduccion AS td
        ON (td.IdTipoDeduccion = de.IdTipoDeduccion)
    LEFT JOIN dbo.PlanillaMesXEmpleado AS pme
        ON (pme.IdEmpleado = pse.IdEmpleado)
       AND (pme.IdMesPlanilla = @vIdMesPlanilla)
    WHERE (pse.IdSemanaPlanilla = @vIdSemanaPlanilla)
      AND (td.EsPorcentual = 1)
      AND (de.FechaInicio <= @inFechaJueves)
      AND (de.FechaFin IS NULL OR de.FechaFin >= @inFechaJueves);

    -- Tabla variable con las deducciones de monto fijo a aplicar por empleado
    DECLARE @tDeduccionesFijas TABLE (
        IdPlanillaSemXEmpleado   INT
      , IdPlanillaMesXEmpleado   INT
      , IdTipoDeduccion          INT
      , Monto                    DECIMAL(12,2)
    );

    INSERT INTO @tDeduccionesFijas (
        IdPlanillaSemXEmpleado
      , IdPlanillaMesXEmpleado
      , IdTipoDeduccion
      , Monto
    )
    SELECT
        pse.IdPlanillaSemXEmpleado
      , pme.IdPlanillaMesXEmpleado
      , de.IdTipoDeduccion
      , ROUND(de.Valor / @vCantidadJueves, 2)
    FROM dbo.PlanillaSemXEmpleado AS pse
    INNER JOIN dbo.DeduccionEmpleado AS de
        ON (de.IdEmpleado = pse.IdEmpleado)
    INNER JOIN dbo.TipoDeduccion AS td
        ON (td.IdTipoDeduccion = de.IdTipoDeduccion)
    LEFT JOIN dbo.PlanillaMesXEmpleado AS pme
        ON (pme.IdEmpleado = pse.IdEmpleado)
       AND (pme.IdMesPlanilla = @vIdMesPlanilla)
    WHERE (pse.IdSemanaPlanilla = @vIdSemanaPlanilla)
      AND (td.EsPorcentual = 0)
      AND (de.Valor > 0)
      AND (de.FechaInicio <= @inFechaJueves)
      AND (de.FechaFin IS NULL OR de.FechaFin >= @inFechaJueves);

    --Transaccion: insertar movimientos y actualizar acumulados

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Insertar movimientos de debito por deducciones porcentuales
        INSERT INTO dbo.MovimientoPlanilla (
            IdPlanillaSemXEmpleado
          , IdTipoMovimiento
          , Fecha
          , Cantidad
          , Monto
        )
        SELECT
            dp.IdPlanillaSemXEmpleado
          , td.IdTipoMovimiento
          , @inFechaJueves
          , 0
          , -dp.Monto
        FROM @tDeduccionesPct AS dp
        INNER JOIN dbo.TipoDeduccion AS td
            ON (td.IdTipoDeduccion = dp.IdTipoDeduccion);

        --Insertar movimientos de debito por deducciones fijas
        INSERT INTO dbo.MovimientoPlanilla (
            IdPlanillaSemXEmpleado
          , IdTipoMovimiento
          , Fecha
          , Cantidad
          , Monto
        )
        SELECT
            df.IdPlanillaSemXEmpleado
          , td.IdTipoMovimiento
          , @inFechaJueves
          , 0
          , -df.Monto
        FROM @tDeduccionesFijas AS df
        INNER JOIN dbo.TipoDeduccion AS td
            ON (td.IdTipoDeduccion = df.IdTipoDeduccion);

