import Link from 'next/link';
import { Card, Nav, Button, ListGroup, Accordion } from 'react-bootstrap';

const Explore = ({families, gallsByFamily}) => {
    return (
        <Card>
        <Card.Header>
            <Nav variant="tabs" defaultActiveKey="#first">
                <Nav.Item>
                    <Nav.Link href="#first">Galls</Nav.Link>
                </Nav.Item>
                <Nav.Item>
                    <Nav.Link href="#link">Hosts</Nav.Link>
                </Nav.Item>
            </Nav>
        </Card.Header>
        <Card.Body>
            <Card.Title>Browse Galls</Card.Title>
            <Card.Text>
                By Family
            </Card.Text>
            <Accordion>
                {families.map( (f) =>
                    <Card key={f.family_id}>
                        <Card.Header>
                            <Accordion.Toggle as={Button} variant="light" eventKey={f.family_id}>
                                <i>{f.name}</i> - {f.description}
                            </Accordion.Toggle>
                        </Card.Header>
                        <Accordion.Collapse eventKey={f.family_id}>
                            <Card.Body>
                                <ListGroup>
                                    {gallsByFamily[f.name].map( (g) =>
                                        <ListGroup.Item key={g.species_id}>
                                            <Link href={"gall/[id]"} as={`gall/${g.species_id}`}><a>{g.name}</a></Link>
                                        </ListGroup.Item>   
                                    )}
                                </ListGroup>
                            </Card.Body>
                        </Accordion.Collapse>
                    </Card>
                )}
            </Accordion>
        </Card.Body>
        </Card>
    )
}

// Use static so that this stuff can be built once on the server-side and then cached.
export async function getStaticProps() {
    const response = await fetch('http://localhost:3000/api/gall/family');
    const families = await response.json();

    const gresp = await fetch('http://localhost:3000/api/gall');
    const galls = await gresp.json();
    function g(acc, cur) {
        if (acc.get(cur['family'])) {
            acc.get(cur['family']).push(cur)
        } else {
            acc.set(cur['family'], [cur])
        }
        return acc;
    }
    const gallsByFamily = galls.reduce(g, new Map());

    return { props: {
           families: families,
           gallsByFamily: Object.fromEntries(gallsByFamily),
        }
    }
}

export default Explore;