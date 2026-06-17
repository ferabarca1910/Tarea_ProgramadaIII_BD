
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


