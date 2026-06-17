
--Carga de catalogos en PlanillaObrera
--Ejecutar DESPUES de sp_catalogos.sql


USE PlanillaObrera;
GO

DECLARE @vXML XML;
DECLARE @vResultCode INT = 0;

--Leer el XML desde el archivo en disco
--SINGLE_BLOB lee el archivo como binario y lo castea a XML
SET @vXML = (
    SELECT CAST(BulkColumn AS XML)
    FROM OPENROWSET(
        BULK '/home/Farola/Documents/Tarea_ProgramadaIII_BD/bd/catalogos.xml'
      , SINGLE_BLOB
    ) AS x
);

--Llamar al SP maestro que carga todos los catalogos en orden
EXEC dbo.sp_CargarCatalogos
    @inXML = @vXML
  ,@outResultCode = @vResultCode OUTPUT;

--0= exito, cualquier otro valor indica error
SELECT @vResultCode AS ResultCode;
GO