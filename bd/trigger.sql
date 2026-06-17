
--Al insertar un empleado, asociarlo automaticamente
--con todas las deducciones obligatorias


USE PlanillaObrera;
GO

SET ANSI_NULLS ON;
GO

SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.trg_AsociarDeducciones', 'TR') IS NOT NULL
    DROP TRIGGER dbo.trg_AsociarDeducciones;
GO

CREATE TRIGGER dbo.trg_AsociarDeducciones
ON dbo.Empleado
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        INSERT INTO dbo.DeduccionEmpleado (
            IdEmpleado
          , IdTipoDeduccion
          , Valor
          , FechaInicio
          , FechaFin
        )
        SELECT
            i.IdEmpleado
          , td.IdTipoDeduccion
          , td.Valor   
          , i.FechaIngreso 
          , NULL             
        FROM inserted AS i
        CROSS JOIN dbo.TipoDeduccion AS td
        WHERE (td.EsObligatoria = 1);

    END TRY
    BEGIN CATCH
        INSERT INTO dbo.DBErrors (
            NombreSP
          , Mensaje
          , Severidad
          , Estado
          , Linea
        )
        VALUES (
            'trg_AsociarDeducciones'
          , ERROR_MESSAGE()
          , ERROR_SEVERITY()
          , ERROR_STATE()
          , ERROR_LINE()
        );

    END CATCH;

END;
GO

PRINT 'Trigger trg_AsociarDeducciones creado exitosamente.';
GO
