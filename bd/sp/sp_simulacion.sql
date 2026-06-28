--======================================================================
-- sp_simulacion.sql
-- Simulación de planilla obrera
-- CORREGIDO:
--   1. Iteración por fechas CONSECUTIVAS (no salta fechas faltantes en XML)
--   2. Procesamiento de asistencias TRANSACCIONAL POR EMPLEADO
--======================================================================

USE PlanillaObrera;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

--======================================================================
-- Función auxiliar: determina si una fecha es domingo o feriado
--======================================================================
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
        FROM   dbo.Feriado AS f
        WHERE  (f.Fecha = @inFecha)
    )
        SET @vEsFeriadoODomingo = 1;
    RETURN @vEsFeriadoODomingo;
END;
GO

--======================================================================
-- Función auxiliar: último jueves de un mes
--======================================================================
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
        CAST(CAST(@inAnio AS VARCHAR(4))
           + '-' + RIGHT('0' + CAST(@inMes AS VARCHAR(2)), 2)
           + '-01' AS DATE)
    );
    SET @vDia = @vUltimoDia;
    WHILE (DATEPART(WEEKDAY, @vDia) <> 5)
        SET @vDia = DATEADD(DAY, -1, @vDia);
    RETURN @vDia;
END;
GO
--======================================================================
-- Función auxiliar: cuenta jueves entre dos fechas
--======================================================================
IF OBJECT_ID('dbo.fn_ContarJueves', 'FN') IS NOT NULL
    DROP FUNCTION dbo.fn_ContarJueves;
GO

CREATE FUNCTION dbo.fn_ContarJueves(@inFechaInicio DATE, @inFechaFin DATE)
RETURNS TINYINT
AS
BEGIN
    DECLARE @vCantidad TINYINT = 0;
    DECLARE @vFecha    DATE    = @inFechaInicio;
    WHILE (@vFecha <= @inFechaFin)
    BEGIN
        IF (DATEPART(WEEKDAY, @vFecha) = 5)
            SET @vCantidad = @vCantidad + 1;
        SET @vFecha = DATEADD(DAY, 1, @vFecha);
    END;
    RETURN @vCantidad;
END;
GO
--======================================================================
-- sp_InicializarSistema
-- Crea el primer MesPlanilla y SemanaPlanilla antes de correr la sim.
--======================================================================
IF OBJECT_ID('dbo.sp_InicializarSistema', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_InicializarSistema;
GO

CREATE PROCEDURE dbo.sp_InicializarSistema
    @inFechaInicioSimulacion DATE       -- Debe ser viernes
  , @outResultCode           INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @outResultCode = 0;

    DECLARE @vFechaFinMes DATE;
    DECLARE @vMesInicio   INT    = MONTH(@inFechaInicioSimulacion);
    DECLARE @vAnioInicio  INT    = YEAR(@inFechaInicioSimulacion);
    DECLARE @vNumJueves   TINYINT;
    DECLARE @vIdMes       INT;
    DECLARE @vFechaFinSem DATE;

    SET @vFechaFinMes = dbo.fn_UltimoJuevesDelMes(@vAnioInicio, @vMesInicio);
    SET @vNumJueves   = dbo.fn_ContarJueves(@inFechaInicioSimulacion, @vFechaFinMes);
    -- Primera semana: viernes de inicio → jueves (6 días después)
    SET @vFechaFinSem = DATEADD(DAY, 6, @inFechaInicioSimulacion);

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO dbo.MesPlanilla (FechaInicio, FechaFin, CantidadJueves, Cerrado)
        VALUES (@inFechaInicioSimulacion, @vFechaFinMes, @vNumJueves, 0);
        SET @vIdMes = SCOPE_IDENTITY();

        INSERT INTO dbo.SemanaPlanilla (IdMesPlanilla, FechaInicio, FechaFin, Cerrada)
        VALUES (@vIdMes, @inFechaInicioSimulacion, @vFechaFinSem, 0);

        COMMIT TRANSACTION;
        PRINT 'Sistema inicializado. Primera semana: '
            + CONVERT(VARCHAR, @inFechaInicioSimulacion, 103)
            + ' - ' + CONVERT(VARCHAR, @vFechaFinSem, 103);
    END TRY
    BEGIN CATCH
        IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION;
        SET @outResultCode = 50008;
        INSERT INTO dbo.DBErrors (NombreSP, Mensaje, Severidad, Estado, Linea)
        VALUES ('sp_InicializarSistema', ERROR_MESSAGE(), ERROR_SEVERITY(), ERROR_STATE(), ERROR_LINE());
    END CATCH;
END;
GO
--======================================================================
-- sp_ProcesarAsistenciaEmpleado
-- Procesa la asistencia de UN empleado en una transacción atómica.
-- Si falla, solo afecta a ese empleado — los demás siguen procesándose.
--======================================================================
IF OBJECT_ID('dbo.sp_ProcesarAsistenciaEmpleado', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_ProcesarAsistenciaEmpleado;
GO

CREATE PROCEDURE dbo.sp_ProcesarAsistenciaEmpleado
    @inValorDocumento    VARCHAR(30)
  , @inFechaHoraEntrada  DATETIME
  , @inFechaHoraSalida   DATETIME
  , @inIdUsuarioSistema  INT
  , @inIPOrigen          VARCHAR(45) = '127.0.0.1'
  , @outResultCode       INT         OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @outResultCode = 0;

    -- Variables de búsqueda (fuera de la transacción para detectar errores de datos)
    DECLARE @vIdEmpleado              INT;
    DECLARE @vSalarioXHora            DECIMAL(10,2);
    DECLARE @vFechaEntrada            DATE = CAST(@inFechaHoraEntrada AS DATE);
    DECLARE @vIdTipoJornada           INT;
    DECLARE @vIdPlanillaSemXEmpleado  INT;
    DECLARE @vFinJornadaDT            DATETIME;

    -- Obtener empleado y salario
    SELECT
        @vIdEmpleado  = e.IdEmpleado
      , @vSalarioXHora = p.SalarioXHora
    FROM   dbo.Empleado AS e
    INNER JOIN dbo.Puesto AS p ON (p.IdPuesto = e.IdPuesto)
    WHERE  (e.ValorDocumentoIdentidad = @inValorDocumento)
      AND  (e.Activo = 1);

    IF (@vIdEmpleado IS NULL)
    BEGIN
        SET @outResultCode = 50012;
        RETURN;
    END;

    -- Obtener jornada de la semana actual
    SELECT TOP (1)
        @vIdTipoJornada = jes.IdTipoJornada
    FROM   dbo.JornadaEmpleadoSemana AS jes
    WHERE  (jes.IdEmpleado = @vIdEmpleado)
      AND  (jes.FechaInicioSemana <= @vFechaEntrada)
    ORDER BY jes.FechaInicioSemana DESC;

    IF (@vIdTipoJornada IS NULL)
    BEGIN
        SET @outResultCode = 50013;
        RETURN;
    END;

    -- Calcular fin de jornada (nocturna cruza medianoche)
    SELECT
        @vFinJornadaDT =
            CASE
                WHEN (tj.HoraFin <= tj.HoraInicio)
                    THEN CAST(DATEADD(DAY, 1, @vFechaEntrada) AS DATETIME)
                       + CAST(tj.HoraFin AS DATETIME)
                       - CAST('00:00:00' AS DATETIME)
                ELSE CAST(@vFechaEntrada AS DATETIME)
                   + CAST(tj.HoraFin AS DATETIME)
                   - CAST('00:00:00' AS DATETIME)
            END
    FROM dbo.TipoJornada AS tj
    WHERE (tj.IdTipoJornada = @vIdTipoJornada);

    -- Obtener planilla semanal abierta
    SELECT TOP (1)
        @vIdPlanillaSemXEmpleado = pse.IdPlanillaSemXEmpleado
    FROM   dbo.PlanillaSemXEmpleado AS pse
    INNER JOIN dbo.SemanaPlanilla   AS sp ON (sp.IdSemanaPlanilla = pse.IdSemanaPlanilla)
    WHERE  (pse.IdEmpleado  = @vIdEmpleado)
      AND  (sp.Cerrada      = 0)
      AND  (sp.FechaInicio  <= @vFechaEntrada)
      AND  (sp.FechaFin     >= @vFechaEntrada);

    IF (@vIdPlanillaSemXEmpleado IS NULL)
    BEGIN
        SET @outResultCode = 50014;
        RETURN;
    END;

    -- ---- Cálculo de horas ----
    DECLARE @vMinutosTrabajados  INT = DATEDIFF(MINUTE, @inFechaHoraEntrada, @inFechaHoraSalida);
    DECLARE @vMinutosJornada     INT = DATEDIFF(MINUTE, @inFechaHoraEntrada, @vFinJornadaDT);

    IF (@vMinutosJornada < 0) SET @vMinutosJornada = 0;

    DECLARE @vMinutosOrdinarios INT = CASE
        WHEN (@vMinutosTrabajados <= @vMinutosJornada) THEN @vMinutosTrabajados
        ELSE @vMinutosJornada
    END;
    DECLARE @vHorasOrdinarias    INT = @vMinutosOrdinarios / 60;
    DECLARE @vMinutosExtra       INT = CASE
        WHEN (@vMinutosTrabajados > @vMinutosJornada) THEN @vMinutosTrabajados - @vMinutosJornada
        ELSE 0
    END;

    DECLARE @vFechaExtra         DATE = CAST(@vFinJornadaDT AS DATE);
    DECLARE @vEsFerODom          BIT  = dbo.fn_EsFeriadoODomingo(@vFechaExtra);
    DECLARE @vHorasExtraNormales INT  = 0;
    DECLARE @vHorasExtraDobles   INT  = 0;

    IF (@vMinutosExtra > 0)
    BEGIN
        IF (@vEsFerODom = 0)
        BEGIN
            DECLARE @vMinHastaMedNoche INT = DATEDIFF(
                MINUTE,
                @vFinJornadaDT,
                CAST(DATEADD(DAY, 1, CAST(@vFinJornadaDT AS DATE)) AS DATETIME)
            );
            IF (@vMinutosExtra <= @vMinHastaMedNoche)
                SET @vHorasExtraNormales = @vMinutosExtra / 60;
            ELSE
            BEGIN
                DECLARE @vEsSigDiaFerODom BIT = dbo.fn_EsFeriadoODomingo(DATEADD(DAY, 1, @vFechaExtra));
                SET @vHorasExtraNormales = @vMinHastaMedNoche / 60;
                DECLARE @vMinExtraEnSigDia INT = @vMinutosExtra - @vMinHastaMedNoche;
                IF (@vEsSigDiaFerODom = 1)
                    SET @vHorasExtraDobles = @vMinExtraEnSigDia / 60;
                ELSE
                    SET @vHorasExtraNormales = @vHorasExtraNormales + (@vMinExtraEnSigDia / 60);
            END;
        END
        ELSE
            SET @vHorasExtraDobles = @vMinutosExtra / 60;
    END;

    DECLARE @vMontoOrdinario   DECIMAL(12,2) = @vHorasOrdinarias    * @vSalarioXHora;
    DECLARE @vMontoExtraNormal DECIMAL(12,2) = @vHorasExtraNormales * @vSalarioXHora * 1.5;
    DECLARE @vMontoExtraDoble  DECIMAL(12,2) = @vHorasExtraDobles   * @vSalarioXHora * 2.0;

    -- ---- Transacción atómica por empleado ----
    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @vIdMarca INT;
        INSERT INTO dbo.MarcaAsistencia (IdEmpleado, FechaHoraEntrada, FechaHoraSalida, FechaOperacion)
        VALUES (@vIdEmpleado, @inFechaHoraEntrada, @inFechaHoraSalida, @vFechaEntrada);
        SET @vIdMarca = SCOPE_IDENTITY();

        IF (@vHorasOrdinarias > 0)
            INSERT INTO dbo.MovimientoPlanilla (IdPlanillaSemXEmpleado, IdTipoMovimiento, IdMarcaAsistencia, Fecha, Cantidad, Monto)
            VALUES (@vIdPlanillaSemXEmpleado, 1, @vIdMarca, @vFechaEntrada, @vHorasOrdinarias, @vMontoOrdinario);

        IF (@vHorasExtraNormales > 0)
            INSERT INTO dbo.MovimientoPlanilla (IdPlanillaSemXEmpleado, IdTipoMovimiento, IdMarcaAsistencia, Fecha, Cantidad, Monto)
            VALUES (@vIdPlanillaSemXEmpleado, 2, @vIdMarca, @vFechaEntrada, @vHorasExtraNormales, @vMontoExtraNormal);

        IF (@vHorasExtraDobles > 0)
            INSERT INTO dbo.MovimientoPlanilla (IdPlanillaSemXEmpleado, IdTipoMovimiento, IdMarcaAsistencia, Fecha, Cantidad, Monto)
            VALUES (@vIdPlanillaSemXEmpleado, 3, @vIdMarca, @vFechaEntrada, @vHorasExtraDobles, @vMontoExtraDoble);

        -- Acumular en planilla semanal del empleado
        UPDATE dbo.PlanillaSemXEmpleado
        SET
            SalarioBruto       = SalarioBruto       + @vMontoOrdinario + @vMontoExtraNormal + @vMontoExtraDoble
          , HorasOrdinarias    = HorasOrdinarias    + @vHorasOrdinarias
          , HorasExtraNormales = HorasExtraNormales + @vHorasExtraNormales
          , HorasExtraDobles   = HorasExtraDobles   + @vHorasExtraDobles
        WHERE (IdPlanillaSemXEmpleado = @vIdPlanillaSemXEmpleado);

        -- Bitácora
        INSERT INTO dbo.BitacoraEvento (IdUsuario, IdTipoEvento, IPOrigen, Parametros)
        VALUES (
            @inIdUsuarioSistema
          , 22
          , @inIPOrigen
          , CONCAT(N'{"doc":"', @inValorDocumento
                 , N'","entrada":"', CONVERT(VARCHAR, @inFechaHoraEntrada, 120)
                 , N'","salida":"',  CONVERT(VARCHAR, @inFechaHoraSalida,  120)
                 , N'"}')
        );

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION;
        SET @outResultCode = 50008;
        INSERT INTO dbo.DBErrors (NombreSP, Mensaje, Severidad, Estado, Linea)
        VALUES ('sp_ProcesarAsistenciaEmpleado', ERROR_MESSAGE(), ERROR_SEVERITY(), ERROR_STATE(), ERROR_LINE());
        -- NO re-lanzamos el error: el empleado falló pero la simulación continúa
    END CATCH;
END;
GO
--======================================================================
-- sp_CierreSemanal
--======================================================================
IF OBJECT_ID('dbo.sp_CierreSemanal', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_CierreSemanal;
GO

CREATE PROCEDURE dbo.sp_CierreSemanal
    @inFechaJueves       DATE
  , @inIdUsuarioSistema  INT
  , @inIPOrigen          VARCHAR(45) = '127.0.0.1'
  , @outResultCode       INT         OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @outResultCode = 0;

    DECLARE @vIdSemanaPlanilla INT;
    DECLARE @vIdMesPlanilla    INT;
    DECLARE @vCantidadJueves   TINYINT;

    SELECT
        @vIdSemanaPlanilla = sp.IdSemanaPlanilla
      , @vIdMesPlanilla    = sp.IdMesPlanilla
    FROM dbo.SemanaPlanilla AS sp
    WHERE (sp.FechaFin = @inFechaJueves)
      AND (sp.Cerrada  = 0);

    IF (@vIdSemanaPlanilla IS NULL)
    BEGIN
        SET @outResultCode = 50015;
        RETURN;
    END;

    SELECT @vCantidadJueves = mp.CantidadJueves
    FROM   dbo.MesPlanilla AS mp
    WHERE  (mp.IdMesPlanilla = @vIdMesPlanilla);

    -- Pre-calcular todas las deducciones (set-based, sin cursores)
    DECLARE @tDeduccionesPct TABLE (
        IdPlanillaSemXEmpleado INT
      , IdPlanillaMesXEmpleado INT
      , IdTipoDeduccion        INT
      , IdTipoMovimiento       INT
      , Monto                  DECIMAL(12,2)
    );

    INSERT INTO @tDeduccionesPct (IdPlanillaSemXEmpleado, IdPlanillaMesXEmpleado, IdTipoDeduccion, IdTipoMovimiento, Monto)
    SELECT
        pse.IdPlanillaSemXEmpleado
      , pme.IdPlanillaMesXEmpleado
      , de.IdTipoDeduccion
      , td.IdTipoMovimiento
      , ROUND(pse.SalarioBruto * td.Valor, 2)
    FROM   dbo.PlanillaSemXEmpleado AS pse
    INNER JOIN dbo.DeduccionEmpleado  AS de  ON (de.IdEmpleado      = pse.IdEmpleado)
    INNER JOIN dbo.TipoDeduccion      AS td  ON (td.IdTipoDeduccion = de.IdTipoDeduccion)
    LEFT  JOIN dbo.PlanillaMesXEmpleado AS pme
           ON (pme.IdEmpleado   = pse.IdEmpleado)
          AND (pme.IdMesPlanilla = @vIdMesPlanilla)
    WHERE  (pse.IdSemanaPlanilla = @vIdSemanaPlanilla)
      AND  (td.EsPorcentual      = 1)
      AND  (de.FechaInicio       <= @inFechaJueves)
      AND  (de.FechaFin IS NULL OR de.FechaFin >= @inFechaJueves);

    DECLARE @tDeduccionesFijas TABLE (
        IdPlanillaSemXEmpleado INT
      , IdPlanillaMesXEmpleado INT
      , IdTipoDeduccion        INT
      , IdTipoMovimiento       INT
      , Monto                  DECIMAL(12,2)
    );

    INSERT INTO @tDeduccionesFijas (IdPlanillaSemXEmpleado, IdPlanillaMesXEmpleado, IdTipoDeduccion, IdTipoMovimiento, Monto)
    SELECT
        pse.IdPlanillaSemXEmpleado
      , pme.IdPlanillaMesXEmpleado
      , de.IdTipoDeduccion
      , td.IdTipoMovimiento
      , ROUND(de.Valor / @vCantidadJueves, 2)
    FROM   dbo.PlanillaSemXEmpleado AS pse
    INNER JOIN dbo.DeduccionEmpleado  AS de  ON (de.IdEmpleado      = pse.IdEmpleado)
    INNER JOIN dbo.TipoDeduccion      AS td  ON (td.IdTipoDeduccion = de.IdTipoDeduccion)
    LEFT  JOIN dbo.PlanillaMesXEmpleado AS pme
           ON (pme.IdEmpleado   = pse.IdEmpleado)
          AND (pme.IdMesPlanilla = @vIdMesPlanilla)
    WHERE  (pse.IdSemanaPlanilla = @vIdSemanaPlanilla)
      AND  (td.EsPorcentual      = 0)
      AND  (de.Valor             > 0)
      AND  (de.FechaInicio       <= @inFechaJueves)
      AND  (de.FechaFin IS NULL OR de.FechaFin >= @inFechaJueves);

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Movimientos de débito porcentuales
        INSERT INTO dbo.MovimientoPlanilla (IdPlanillaSemXEmpleado, IdTipoMovimiento, Fecha, Cantidad, Monto)
        SELECT dp.IdPlanillaSemXEmpleado, dp.IdTipoMovimiento, @inFechaJueves, 0, -dp.Monto
        FROM   @tDeduccionesPct AS dp;

        -- Movimientos de débito fijos
        INSERT INTO dbo.MovimientoPlanilla (IdPlanillaSemXEmpleado, IdTipoMovimiento, Fecha, Cantidad, Monto)
        SELECT df.IdPlanillaSemXEmpleado, df.IdTipoMovimiento, @inFechaJueves, 0, -df.Monto
        FROM   @tDeduccionesFijas AS df;

        -- Actualizar TotalDeducciones y SalarioNeto en PlanillaSemXEmpleado
        UPDATE pse
        SET
            pse.TotalDeducciones = ISNULL(t.MontoTotal, 0)
          , pse.SalarioNeto      = pse.SalarioBruto - ISNULL(t.MontoTotal, 0)
        FROM dbo.PlanillaSemXEmpleado AS pse
        LEFT JOIN (
            SELECT IdPlanillaSemXEmpleado, SUM(Monto) AS MontoTotal
            FROM (
                SELECT IdPlanillaSemXEmpleado, Monto FROM @tDeduccionesPct
                UNION ALL
                SELECT IdPlanillaSemXEmpleado, Monto FROM @tDeduccionesFijas
            ) AS u
            GROUP BY IdPlanillaSemXEmpleado
        ) AS t ON (t.IdPlanillaSemXEmpleado = pse.IdPlanillaSemXEmpleado)
        WHERE (pse.IdSemanaPlanilla = @vIdSemanaPlanilla);

        -- Acumular en DeduccionXEmpleadoXMes (porcentuales)
        MERGE dbo.DeduccionXEmpleadoXMes AS dest
        USING (
            SELECT IdPlanillaMesXEmpleado, IdTipoDeduccion, SUM(Monto) AS Monto
            FROM   @tDeduccionesPct
            WHERE  (IdPlanillaMesXEmpleado IS NOT NULL)
            GROUP BY IdPlanillaMesXEmpleado, IdTipoDeduccion
        ) AS src
        ON    (dest.IdPlanillaMesXEmpleado = src.IdPlanillaMesXEmpleado)
          AND (dest.IdTipoDeduccion        = src.IdTipoDeduccion)
        WHEN MATCHED     THEN UPDATE SET MontoTotal = ISNULL(MontoTotal, 0) + src.Monto
        WHEN NOT MATCHED THEN INSERT (IdPlanillaMesXEmpleado, IdTipoDeduccion, MontoTotal)
                              VALUES (src.IdPlanillaMesXEmpleado, src.IdTipoDeduccion, src.Monto);

        -- Acumular en DeduccionXEmpleadoXMes (fijas)
        MERGE dbo.DeduccionXEmpleadoXMes AS dest
        USING (
            SELECT IdPlanillaMesXEmpleado, IdTipoDeduccion, SUM(Monto) AS Monto
            FROM   @tDeduccionesFijas
            WHERE  (IdPlanillaMesXEmpleado IS NOT NULL)
            GROUP BY IdPlanillaMesXEmpleado, IdTipoDeduccion
        ) AS src
        ON    (dest.IdPlanillaMesXEmpleado = src.IdPlanillaMesXEmpleado)
          AND (dest.IdTipoDeduccion        = src.IdTipoDeduccion)
        WHEN MATCHED     THEN UPDATE SET MontoTotal = ISNULL(MontoTotal, 0) + src.Monto
        WHEN NOT MATCHED THEN INSERT (IdPlanillaMesXEmpleado, IdTipoDeduccion, MontoTotal)
                              VALUES (src.IdPlanillaMesXEmpleado, src.IdTipoDeduccion, src.Monto);

        -- Acumular en PlanillaMesXEmpleado
        UPDATE pme
        SET
            SalarioBrutoMensual     = ISNULL(pme.SalarioBrutoMensual, 0)     + ISNULL(pse.SalarioBruto,       0)
          , TotalDeduccionesMensual = ISNULL(pme.TotalDeduccionesMensual, 0) + ISNULL(pse.TotalDeducciones,   0)
          , SalarioNetoMensual      = ISNULL(pme.SalarioNetoMensual, 0)      + ISNULL(pse.SalarioNeto,        0)
        FROM dbo.PlanillaMesXEmpleado AS pme
        INNER JOIN dbo.PlanillaSemXEmpleado AS pse ON (pse.IdEmpleado = pme.IdEmpleado)
        WHERE (pse.IdSemanaPlanilla = @vIdSemanaPlanilla)
          AND (pme.IdMesPlanilla   = @vIdMesPlanilla);

        -- Cerrar la semana
        UPDATE dbo.SemanaPlanilla SET Cerrada = 1 WHERE (IdSemanaPlanilla = @vIdSemanaPlanilla);

        INSERT INTO dbo.BitacoraEvento (IdUsuario, IdTipoEvento, IPOrigen, Parametros)
        VALUES (
            @inIdUsuarioSistema
          , 22
          , @inIPOrigen
          , CONCAT(N'{"cierre_semanal":"', CONVERT(VARCHAR, @inFechaJueves, 120), N'"}')
        );

        COMMIT TRANSACTION;
        PRINT 'Cierre semanal del ' + CONVERT(VARCHAR, @inFechaJueves, 103) + ' completado.';
    END TRY
    BEGIN CATCH
        IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION;
        SET @outResultCode = 50008;
        INSERT INTO dbo.DBErrors (NombreSP, Mensaje, Severidad, Estado, Linea)
        VALUES ('sp_CierreSemanal', ERROR_MESSAGE(), ERROR_SEVERITY(), ERROR_STATE(), ERROR_LINE());
    END CATCH;
END;
GO
