
USE PlanillaObrera;
GO
 
IF OBJECT_ID('dbo.fn_UltimoJuevesDelMes', 'FN') IS NOT NULL DROP FUNCTION dbo.fn_UltimoJuevesDelMes;
GO
CREATE FUNCTION dbo.fn_UltimoJuevesDelMes(@anio INT, @mes INT)
RETURNS DATE
AS
BEGIN
    DECLARE @ultimoDia DATE = EOMONTH(CAST(CAST(@anio AS VARCHAR) + '-' + RIGHT('0'+CAST(@mes AS VARCHAR),2) + '-01' AS DATE));
    DECLARE @dia DATE = @ultimoDia;
    WHILE DATEPART(WEEKDAY, @dia) <> 5   
        SET @dia = DATEADD(DAY, -1, @dia);
    RETURN @dia;
END;
GO
 

IF OBJECT_ID('dbo.fn_ContarJueves', 'FN') IS NOT NULL DROP FUNCTION dbo.fn_ContarJueves;
GO
CREATE FUNCTION dbo.fn_ContarJueves(@fechaInicio DATE, @fechaFin DATE)
RETURNS TINYINT
AS
BEGIN
    DECLARE @count TINYINT = 0;
    DECLARE @f DATE = @fechaInicio;
    WHILE @f <= @fechaFin
    BEGIN
        IF DATEPART(WEEKDAY, @f) = 5 SET @count = @count + 1;
        SET @f = DATEADD(DAY, 1, @f);
    END;
    RETURN @count;
END;
GO
 
IF OBJECT_ID('sp_EjecutarSimulacion', 'P') IS NOT NULL DROP PROCEDURE sp_EjecutarSimulacion;
GO
CREATE PROCEDURE sp_EjecutarSimulacion
    @xmlOperacion       XML,
    @IdUsuarioSistema   INT = 1,    
    @IPOrigen           VARCHAR(45) = '127.0.0.1'
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
 
        CREATE TABLE #Fechas (Fecha DATE, XMLNodo XML);
 
        INSERT INTO #Fechas (Fecha, XMLNodo)
        SELECT
            CAST(nodo.value('@Fecha', 'VARCHAR(10)') AS DATE),
            nodo.query('.')
        FROM @xmlOperacion.nodes('/Operacion/FechaOperacion') AS T(nodo)
        ORDER BY CAST(nodo.value('@Fecha', 'VARCHAR(10)') AS DATE);
 
        DECLARE @FechaActual    DATE;
        DECLARE @NodoXML        XML;
        DECLARE @EsJueves       BIT;
        DECLARE @DiaSemana      INT;
 
        DECLARE cur_fechas CURSOR LOCAL FAST_FORWARD FOR
            SELECT Fecha, XMLNodo FROM #Fechas ORDER BY Fecha;
 
        OPEN cur_fechas;
        FETCH NEXT FROM cur_fechas INTO @FechaActual, @NodoXML;
 
        WHILE @@FETCH_STATUS = 0
        BEGIN
            PRINT '--- Procesando fecha: ' + CONVERT(VARCHAR, @FechaActual, 103) + ' ---';
 
            SET @DiaSemana = DATEPART(WEEKDAY, @FechaActual);  
            SET @EsJueves  = CASE WHEN @DiaSemana = 5 THEN 1 ELSE 0 END;
