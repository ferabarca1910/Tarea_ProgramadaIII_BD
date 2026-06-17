--Ejecuta la simulacion de planilla desde operacion.xml
--Ejecutar DESPUES de sp_admin.sql y sp_simulacion.sql

USE PlanillaObrera;
GO

SET ANSI_NULLS ON;
GO

SET QUOTED_IDENTIFIER ON;
GO

DECLARE @vXML XML;
DECLARE @vFechaPrimeraOperacion DATE;
DECLARE @vFechaInicioSimulacion DATE;
DECLARE @vResultCodeInicializar INT = 0;
DECLARE @vResultCodeSimulacion INT = 0;

SET @vXML = (
    SELECT CAST(BulkColumn AS XML)
    FROM OPENROWSET(
        BULK '/home/Farola/Documents/Tarea_ProgramadaIII_BD/bd/operacion.xml'
      , SINGLE_BLOB
    ) AS x
);

SELECT
    @vFechaPrimeraOperacion = MIN(CAST(nodo.value('@Fecha', 'VARCHAR(10)') AS DATE))
FROM @vXML.nodes('/Operaciones/FechaOperacion') AS x(nodo);

SET @vFechaInicioSimulacion = DATEADD(DAY, 1, @vFechaPrimeraOperacion);

EXEC dbo.sp_InicializarSistema
    @inFechaInicioSimulacion = @vFechaInicioSimulacion
  ,@outResultCode = @vResultCodeInicializar OUTPUT;

IF (@vResultCodeInicializar = 0)
BEGIN

    EXEC dbo.sp_EjecutarSimulacion
        @inXMLOperacion = @vXML
      ,@inIdUsuarioSistema = 1
      ,@inIPOrigen = '127.0.0.1'
      ,@outResultCode = @vResultCodeSimulacion OUTPUT;

END;

SELECT
    @vFechaPrimeraOperacion AS FechaPrimeraOperacion
  ,@vFechaInicioSimulacion AS FechaInicioSimulacion
  ,@vResultCodeInicializar AS ResultCodeInicializar
  ,@vResultCodeSimulacion AS ResultCodeSimulacion;
GO
