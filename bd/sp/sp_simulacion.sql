
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
            DECLARE @docValorDoc        VARCHAR(30);
            DECLARE @docNombrePuesto    VARCHAR(100);
            DECLARE @docUsername        VARCHAR(50);
            DECLARE @docPassword        VARCHAR(255);
            DECLARE @docIdEmpNuevo      INT;
 
            DECLARE cur_nuevos CURSOR LOCAL FAST_FORWARD FOR
                SELECT
                    nodo.value('@Nombre',             'VARCHAR(150)'),
                    nodo.value('@ValorTipoDocumento', 'VARCHAR(30)'),
                    nodo.value('@IdPuesto',           'VARCHAR(100)'),   -- nombre del puesto
                    nodo.value('@dbo.Usuario',            'VARCHAR(50)'),
                    nodo.value('@Password',           'VARCHAR(255)')
                FROM @NodoXML.nodes('/FechaOperacion/NuevosEmpleados/NuevoEmpleado') AS T(nodo);
 
            OPEN cur_nuevos;
            FETCH NEXT FROM cur_nuevos INTO @docNombre, @docValorDoc,
                                            @docNombrePuesto, @docUsername, @docPassword;
            WHILE @@FETCH_STATUS = 0
            BEGIN
                EXEC sp_InsertarEmpleado
                    @Nombre          = @docNombre,
                    @ValorDocumento  = @docValorDoc,
                    @NombrePuesto    = @docNombrePuesto,
                    @Username        = @docUsername,
                    @Password        = @docPassword,
                    @FechaIngreso    = @FechaActual,
                    @IdUsuarioAdmin  = @IdUsuarioSistema,
                    @IPOrigen        = @IPOrigen,
                    @IdEmpleadoNuevo = @docIdEmpNuevo OUTPUT;
 
                FETCH NEXT FROM cur_nuevos INTO @docNombre, @docValorDoc,
                                                @docNombrePuesto, @docUsername, @docPassword;
            END;
            CLOSE cur_nuevos; DEALLOCATE cur_nuevos;
 
            DECLARE @docValorDocElim VARCHAR(30);
 
            DECLARE cur_elim CURSOR LOCAL FAST_FORWARD FOR
                SELECT nodo.value('@ValorTipoDocumento', 'VARCHAR(30)')
                FROM @NodoXML.nodes('/FechaOperacion/EliminarEmpleados/EliminarEmpleado') AS T(nodo);
 
            OPEN cur_elim;
            FETCH NEXT FROM cur_elim INTO @docValorDocElim;
            WHILE @@FETCH_STATUS = 0
            BEGIN
                EXEC sp_EliminarEmpleado @docValorDocElim, @IdUsuarioSistema, @IPOrigen;
                FETCH NEXT FROM cur_elim INTO @docValorDocElim;
            END;
            CLOSE cur_elim; DEALLOCATE cur_elim;
 
            DECLARE @docValorDocAsoc    VARCHAR(30);
            DECLARE @docIdTipoDed       INT;
            DECLARE @docMonto           DECIMAL(12,2);
            DECLARE @FechaInicioAsoc    DATE = DATEADD(DAY, 1, @FechaActual); 
 
            DECLARE cur_asoc CURSOR LOCAL FAST_FORWARD FOR
                SELECT
                    nodo.value('@ValorTipoDocumento', 'VARCHAR(30)'),
                    nodo.value('@IdTipoDeduccion',    'INT'),
                    nodo.value('@Monto',              'DECIMAL(12,2)')
                FROM @NodoXML.nodes('/FechaOperacion/AsociacionEmpleadoDeducciones/AsociacionEmpleadoConDeduccion') AS T(nodo);
 
            OPEN cur_asoc;
            FETCH NEXT FROM cur_asoc INTO @docValorDocAsoc, @docIdTipoDed, @docMonto;
            WHILE @@FETCH_STATUS = 0
            BEGIN
                EXEC sp_AsociarDeduccion @docValorDocAsoc, @docIdTipoDed, @docMonto,
                    @FechaInicioAsoc, @IdUsuarioSistema, @IPOrigen;
                FETCH NEXT FROM cur_asoc INTO @docValorDocAsoc, @docIdTipoDed, @docMonto;
            END;
            CLOSE cur_asoc; DEALLOCATE cur_asoc;

            DECLARE @docValorDocDesasoc VARCHAR(30);
            DECLARE @docIdTipoDedDes    INT;
 
            DECLARE cur_desasoc CURSOR LOCAL FAST_FORWARD FOR
                SELECT
                    nodo.value('@ValorTipoDocumento', 'VARCHAR(30)'),
                    nodo.value('@IdTipoDeduccion',    'INT')
                FROM @NodoXML.nodes('/FechaOperacion/DesasociacionEmpleadoDeducciones/DesasociacionEmpleadoConDeduccion') AS T(nodo);
 
            OPEN cur_desasoc;
            FETCH NEXT FROM cur_desasoc INTO @docValorDocDesasoc, @docIdTipoDedDes;
            WHILE @@FETCH_STATUS = 0
            BEGIN
                EXEC sp_DesasociarDeduccion @docValorDocDesasoc, @docIdTipoDedDes,
                    @FechaActual, @IdUsuarioSistema, @IPOrigen;
                FETCH NEXT FROM cur_desasoc INTO @docValorDocDesasoc, @docIdTipoDedDes;
            END;
            CLOSE cur_desasoc; DEALLOCATE cur_desasoc;
 
            DECLARE @docValorDocMarca   VARCHAR(30);
            DECLARE @docEntrada         DATETIME;
            DECLARE @docSalida          DATETIME;
 
            DECLARE cur_marcas CURSOR LOCAL FAST_FORWARD FOR
                SELECT
                    nodo.value('@ValorTipoDocumento', 'VARCHAR(30)'),
                    CAST(nodo.value('@HoraEntrada',   'VARCHAR(20)') AS DATETIME),
                    CAST(nodo.value('@HoraSalida',    'VARCHAR(20)') AS DATETIME)
                FROM @NodoXML.nodes('/FechaOperacion/MarcasAsistencia/MarcaDeAsistencia') AS T(nodo);
 
            OPEN cur_marcas;
            FETCH NEXT FROM cur_marcas INTO @docValorDocMarca, @docEntrada, @docSalida;
            WHILE @@FETCH_STATUS = 0
            BEGIN
                EXEC sp_ProcesarAsistencia
                    @ValorDocumento   = @docValorDocMarca,
                    @FechaHoraEntrada = @docEntrada,
                    @FechaHoraSalida  = @docSalida,
                    @IdUsuarioSistema = @IdUsuarioSistema,
                    @IPOrigen         = @IPOrigen;
 
                FETCH NEXT FROM cur_marcas INTO @docValorDocMarca, @docEntrada, @docSalida;
            END;
            CLOSE cur_marcas; DEALLOCATE cur_marcas;
 
            IF @EsJueves = 1
            BEGIN
                DECLARE @docValorDocJor     VARCHAR(30);
                DECLARE @docIdTipoJornada   INT;
                DECLARE @FechaViernes       DATE = DATEADD(DAY, 1, @FechaActual);  -- el viernes siguiente
 
                DECLARE cur_jornadas CURSOR LOCAL FAST_FORWARD FOR
                    SELECT
                        nodo.value('@ValorTipoDocumento', 'VARCHAR(30)'),
                        nodo.value('@IdTipoJornada',      'INT')
                    FROM @NodoXML.nodes('/FechaOperacion/JornadasProximaSemana/TipoJornadaProximaSemana') AS T(nodo);
 
                OPEN cur_jornadas;
                FETCH NEXT FROM cur_jornadas INTO @docValorDocJor, @docIdTipoJornada;
                WHILE @@FETCH_STATUS = 0
                BEGIN
                    EXEC sp_AsignarJornada @docValorDocJor, @docIdTipoJornada,
                        @FechaViernes, @IdUsuarioSistema, @IPOrigen;
                    FETCH NEXT FROM cur_jornadas INTO @docValorDocJor, @docIdTipoJornada;
                END;
                CLOSE cur_jornadas; DEALLOCATE cur_jornadas;
 
