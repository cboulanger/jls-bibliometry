// Merge journals
UNWIND [
  ['(?i).*j.*law.*context', 'int j law context', 'international journal of law in context'],
  ['(?i).*social.*leg.*studies', 'soc leg stud', 'social & legal studies'],
  ['(?i)(br.* j.?|journal) (of )?law.*society', 'br j law soc', 'british journal of law & society'],
  ['(?i)(j.?|journal) (of )?law.*society', 'j law soc', 'journal of law & society'],
  ['(?i).*(law.*|&) society ?rev.*', 'law soc rev', 'law & society review'],
  ['(?i).*modern law rev.*', 'mod law rev', 'modern law review'],
  ['z.*( f.*)? ?rechtssoziolog.*', 'z rechtssoziolog', 'zeitschrift für rechtssoziologie']
] AS j
MATCH (v:Venue)
  WHERE v.name =~ j[0]
WITH collect(v) AS v2, j
CALL apoc.refactor.mergeNodes(v2, {properties: 'replace', mergeRels: true}) YIELD node
SET node.id = j[1]
SET node.name = j[2]
RETURN node;

//  Clean up garbage venues
MATCH (v:Venue)
  WHERE v.id IN ['id', 'ibid', 'dawn', 'table']
DETACH DELETE v;

// Merge duplicate works
CALL apoc.periodic.`commit`(
"MATCH (w1:Work)-[:PUBLISHED_IN]->(v:Venue)<-[:PUBLISHED_IN]-(w2:Work)
  WHERE id(w1) <> id(w2)
  AND toLower(w1.title) = toLower(w2.title)
  AND w1.year = w2.year
  AND toLower(w1.title) <> toLower(v.name)
  AND toLower(w1.title) <> toLower(v.id)
  AND (w1.id STARTS WITH '10' OR id(w1) < id(w2))
WITH w1, w2
  LIMIT 1
CALL apoc.refactor.mergeNodes([w1, w2], {
  properties:     'discard',
  mergeRels:      true,
  produceSelfRel: false
}) YIELD node
RETURN count(*);");

// Deleting empty author nodes
match (a:Author) where a.family="" and a.given="" detach delete a;

// Remove punctuation in given names
MATCH (a:Author)
SET a.given = replace(replace(a.given, '.', ' '), '-', ' ')
RETURN count(a);

// Initialize all authors and remove punctuation
MATCH (a:Author)
WITH a, [word IN split(a.given, ' ') | left(word, 1)] AS initialsList
SET a.given = CASE WHEN size(initialsList) > 0 THEN
  reduce(acc = '', initial IN initialsList | acc + initial)
  ELSE left(a.given, 1) END
RETURN count(a);

// Updating author's display_name property
match(a:Author)
SET a.display_name = a.family + ', ' + a.given;

// Merging similar author nodes that are co-creators of the same work
MATCH (a:Author)-[:CREATOR_OF]->(:Work)<-[:CREATOR_OF]-(b:Author)
  WHERE a <> b
  AND a.family = b.family
  AND left(a.given,1) = left(b.given,1)
WITH a.family AS family, left(a.given, 1) AS givenInitial, COLLECT(DISTINCT a) AS nodes
  WHERE SIZE(nodes) > 1
CREATE (n:Author {
  display_name: family + ', ' + givenInitial,
  family: family,
  given: givenInitial })
WITH [n] + nodes AS nodes
CALL apoc.refactor.mergeNodes(nodes,{
  properties:"discard",
  mergeRels:true
})
YIELD node
RETURN count(node);

// Merging author nodes with identical display_name
MATCH (a:Author)
WITH a.display_name AS name, COLLECT(a) AS nodes
CALL apoc.refactor.mergeNodes(nodes, {properties: 'replace', mergeRels: true}) YIELD node
RETURN count(node);

// Merging all matching multiple initials into first initial only
MATCH (a:Author)
  WHERE size(a.given) = 1
WITH a
MATCH (b:Author)
  WHERE b.display_name STARTS WITH a.display_name
  AND size(b.given) > 1
WITH a, b, collect(b.given) AS initials, count(DISTINCT substring(b.given, 1)) AS count
  WHERE count = 1
WITH a, collect(b) AS nodesToMerge
CALL apoc.refactor.mergeNodes([a] + nodesToMerge, {properties: 'discard', mergeRels: true}) YIELD node
RETURN count(node);

// Merging "jdoe, " into "doe, j"
MATCH (a:Author)-[:CREATOR_OF]->(:Work)<-[c:CITES]
-(:Work)
With a, count(c) as citeCount
  where citeCount > 10
with distinct a, a.given + a.family + ', ' AS displayName
MATCH (b:Author)
  WHERE a <> b and b.display_name = displayName
CALL apoc.refactor.mergeNodes([a, b], {properties: 'discard', mergeRels: true}) YIELD node
return count(node);

// Merging all Author nodes that are missing a given name into their unambiguous equivalent with given name
MATCH (a:Author)
  WHERE a.given = ''
WITH a
MATCH (b:Author)
  WHERE b.display_name STARTS WITH a.display_name
  AND b.given <> ''
WITH a, b, count(b) AS count
  WHERE count = 1
WITH a, collect(b)[0] AS b
CALL apoc.refactor.mergeNodes([b,a], {properties: 'discard', mergeRels: true}) YIELD node
RETURN count(node);


// Handle different spellings of author names
WITH [
       ["priban", "prïibaânï", "přibáň"],
       ["de sousa santos", "desousasantos"]
     ] AS families
UNWIND families AS familyList
MATCH (a:Author)
  WHERE a.family IN familyList
WITH a.given AS givenName, collect(a) AS nodes
CALL apoc.refactor.mergeNodes(nodes,{
  properties:"discard",
  mergeRels:true
})
YIELD node
RETURN node;


// Create temporal values
MATCH (w:Work)
SET w.decade = toInteger(w.year / 10) * 10,
w.decade = toInteger(w.year / 10) * 10,
w.quinq = toInteger(w.year / 5) * 5;

// Create temporal labels
MATCH (w:Work)
SET w.labelQuinq = apoc.text.`join`([toString(w.quinq), toString(w.quinq + 4)], '-'),
w.labelDecade = apoc.text.`join`([toString(w.decade), toString(w.decade + 9)], '-');
