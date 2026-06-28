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
