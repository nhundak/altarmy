import { Alert, Button, Card, Stack, Table, Text, Title } from '@mantine/core'
import { useAhBlocked, useSetAhBlocked } from '../api/queries'
import { ApiKeysCard } from './ApiKeysCard'
import { ItemLink } from './ItemTooltip'

function AhBlockedCard() {
  const blocked = useAhBlocked()
  const setBlocked = useSetAhBlocked()
  return (
    <Card withBorder>
      <Stack gap="sm">
        <Title order={3}>Never sold on the auction house</Title>
        <Text size="sm" c="dimmed">
          Searches only vendor or disenchant these items. They can still be bought on the auction house.
        </Text>
        {blocked.isError && <Alert color="red">{blocked.error.message}</Alert>}
        {blocked.data && !blocked.data.items.length && (
          <Text size="sm" c="dimmed">
            Use the ⋯ menu on a search result to stop selling an item on the auction house.
          </Text>
        )}
        {blocked.data && blocked.data.items.length > 0 && (
          <Table>
            <Table.Tbody>
              {blocked.data.items.map(({ item_id, added_at }) => {
                const item = blocked.data.details[item_id]
                const name = item?.name ?? `Item ${item_id}`
                return (
                  <Table.Tr key={item_id}>
                    <Table.Td>
                      <ItemLink item={item} name={name} />
                    </Table.Td>
                    <Table.Td>
                      <Text size="sm" c="dimmed">
                        added {added_at} UTC
                      </Text>
                    </Table.Td>
                    <Table.Td ta="right">
                      <Button
                        size="xs"
                        variant="default"
                        aria-label={`Allow ${name} on the auction house`}
                        loading={setBlocked.isPending && setBlocked.variables.itemId === item_id}
                        onClick={() => setBlocked.mutate({ itemId: item_id, blocked: false })}
                      >
                        Remove
                      </Button>
                    </Table.Td>
                  </Table.Tr>
                )
              })}
            </Table.Tbody>
          </Table>
        )}
      </Stack>
    </Card>
  )
}

/** The AH blocks and the watcher's API keys. */
export function ManageTab() {
  return (
    <Stack>
      <AhBlockedCard />
      <ApiKeysCard />
    </Stack>
  )
}
