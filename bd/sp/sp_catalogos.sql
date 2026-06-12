-- ============================================================
-- SP_CATALOGOS: Carga todos los catálogos desde el XML
-- Actualizado según Datos.xml
-- ============================================================

USE PlanillaObrera;
GO

-- ============================================================
-- SP: Cargar TiposDeJornada
-- ============================================================
IF OBJECT_ID('sp_CargarTiposJornada', 'P') IS NOT NULL DROP PROCEDURE sp_CargarTiposJornada;
GO
CREATE PROCEDURE sp_CargarTiposJornada @xmlData XML
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.TipoJornada (IdTipoJornada, Nombre, HoraInicio, HoraFin)
    SELECT
        nodo.value('@id',         'INT'),
        nodo.value('@Nombre',     'VARCHAR(50)'),
        CAST(nodo.value('@HoraInicio', 'VARCHAR(10)') AS TIME),
        CAST(nodo.value('@HoraFin',    'VARCHAR(10)') AS TIME)
    FROM @xmlData.nodes('/Catalogo/TiposDeJornada/TipoDeJornada') AS T(nodo)
    WHERE NOT EXISTS (
        SELECT 1 FROM dbo.TipoJornada WHERE IdTipoJornada = nodo.value('@id','INT')
    );
    PRINT 'TiposDeJornada cargados.';
END;
GO
-- ============================================================
-- SP: Cargar Puestos (mapeo por nombre, PK identity)
-- ============================================================
IF OBJECT_ID('sp_CargarPuestos', 'P') IS NOT NULL DROP PROCEDURE sp_CargarPuestos;
GO
CREATE PROCEDURE sp_CargarPuestos @xmlData XML
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.Puesto (Nombre, SalarioXHora)
    SELECT
        nodo.value('@Nombre',       'VARCHAR(100)'),
        nodo.value('@SalarioXHora', 'DECIMAL(10,2)')
    FROM @xmlData.nodes('/Catalogo/Puestos/dbo.Puesto') AS T(nodo)
    WHERE NOT EXISTS (
        SELECT 1 FROM dbo.Puesto WHERE Nombre = nodo.value('@Nombre','VARCHAR(100)')
    );
    PRINT 'Puestos cargados.';
END;
GO
