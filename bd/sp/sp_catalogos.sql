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
-- ============================================================
-- SP: Cargar TiposDeMovimiento (con campo Accion C/D)
-- ============================================================
IF OBJECT_ID('sp_CargarTiposMovimiento', 'P') IS NOT NULL DROP PROCEDURE sp_CargarTiposMovimiento;
GO
CREATE PROCEDURE sp_CargarTiposMovimiento @xmlData XML
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.TipoMovimiento (IdTipoMovimiento, Nombre, Accion)
    SELECT
        nodo.value('@Id',     'INT'),
        nodo.value('@Nombre', 'VARCHAR(100)'),
        nodo.value('@Accion', 'CHAR(1)')
    FROM @xmlData.nodes('/Catalogo/TiposDeMovimiento/TipoDeMovimiento') AS T(nodo)
    WHERE NOT EXISTS (
        SELECT 1 FROM dbo.TipoMovimiento WHERE IdTipoMovimiento = nodo.value('@Id','INT')
    );
    PRINT 'TiposDeMovimiento cargados.';
END;
GO
-- ============================================================
-- SP: Cargar TiposDeDeduccion
-- FK a dbo.TipoMovimiento resuelta por nombre (atributo dbo.TipoMovimiento)
-- Atributos: EsObligatoria, EsPorcentual (en lugar de Obligatorio/Porcentual)
-- ============================================================
IF OBJECT_ID('sp_CargarTiposDeduccion', 'P') IS NOT NULL DROP PROCEDURE sp_CargarTiposDeduccion;
GO
CREATE PROCEDURE sp_CargarTiposDeduccion @xmlData XML
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.TipoDeduccion (IdTipoDeduccion, Nombre, EsObligatoria, EsPorcentual, Valor, IdTipoMovimiento)
    SELECT
        nodo.value('@Id',            'INT'),
        nodo.value('@Nombre',        'VARCHAR(100)'),
        nodo.value('@EsObligatoria', 'BIT'),
        nodo.value('@EsPorcentual',  'BIT'),
        nodo.value('@Valor',         'DECIMAL(10,4)'),
        tm.IdTipoMovimiento
    FROM @xmlData.nodes('/Catalogo/TiposDeDeduccion/TipoDeDeduccion') AS T(nodo)
    INNER JOIN dbo.TipoMovimiento tm
        ON tm.Nombre = nodo.value('@dbo.TipoMovimiento','VARCHAR(100)')
    WHERE NOT EXISTS (
        SELECT 1 FROM dbo.TipoDeduccion WHERE IdTipoDeduccion = nodo.value('@Id','INT')
    );
    PRINT 'TiposDeDeduccion cargados.';
END;
GO
