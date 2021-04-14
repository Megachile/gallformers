-- Up

PRAGMA foreign_keys=OFF;

-- Simple changes adding gall descriptors per #115
INSERT INTO texture (id, texture, description) VALUES (NULL, 'leafy', '');
INSERT INTO texture (id, texture, description) VALUES (NULL, 'mottled', '');
INSERT INTO texture (id, texture, description) VALUES (NULL, 'succulent', '');
INSERT INTO texture (id, texture, description) VALUES (NULL, 'spiky/thorny', '');
INSERT INTO cells (id, cells, description) VALUES (NULL, 'free-rolling', '');
INSERT INTO walls (id, walls, description) VALUES (NULL, 'radiating-fibers', '');
INSERT INTO walls (id, walls, description) VALUES (NULL, 'spongy', '');

-- #117 clean up duplicate genera

-- a temp table that holds all of the good genera that we want to keep and whose ids we will
-- use to replace the duplicate genera
CREATE TEMP TABLE tax (
    id        INTEGER,
    name      TEXT
);

INSERT INTO [temp].tax (
                           id,
                           name
                       )
                       SELECT id,
                              name
                         FROM taxonomy
                         WHERE type = 'genus'
                        GROUP BY name,
                                 parent_id
                       HAVING count( * ) > 1;

-- a temp table that holds all of the duplicated taxonomy records with the proper ID, i.e., the one from the other temp table
CREATE TEMP TABLE taxdup (
    id        INTEGER,
    name      TEXT,
    proper_id INTEGER
);

INSERT INTO [temp].taxdup (
                              id,
                              name,
                              proper_id
                          )
                          SELECT a.id,
                                 a.name,
                                 b.id
                            FROM taxonomy as a
                            JOIN [temp].tax as b ON a.name = b.name
                           WHERE a.id NOT IN (
                                     SELECT id
                                       FROM [temp].tax
                                 )
AND 
                                 a.name IN (
                                     SELECT name
                                       FROM [temp].tax
                                 )
                                 order by a.name;

-- update all of the records in the speciestaxonomy table that are duplicates with the proper id
-- we use an INGORE here as there are some duplicates relating to the Quercus genus, see next step.
UPDATE OR IGNORE speciestaxonomy
   SET taxonomy_id = (
           SELECT proper_id
             FROM [temp].taxdup
            WHERE id = taxonomy_id
       )
 WHERE taxonomy_id IN (
    SELECT id
      FROM [temp].taxdup
);


-- if there are any leftover that need fixing they are duplicates and we will delete them
-- this was due to an error in the way Sections where handled and only affected some of the Quercus entries
-- this step is not strictly needed since the next step will cascade delete these but I wanted it to be very
-- clear what is happening
DELETE FROM speciestaxonomy
      WHERE taxonomy_id IN (
    SELECT id
      FROM [temp].taxdup
);

-- finally delete the bad records from the taxonomy table
DELETE FROM taxonomy
      WHERE id IN (
    SELECT id
      FROM [temp].taxdup
);

DROP TABLE [temp].tax;
DROP TABLE [temp].taxdup;

VACUUM;

PRAGMA foreign_keys=ON;

--------------------------------------------------------------
-- Down
PRAGMA foreign_keys=OFF;


PRAGMA foreign_keys=ON;
