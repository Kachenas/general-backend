<?php

namespace Tests\Feature\Api\V1;

use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Passport\Passport;
use Tests\TestCase;

class RoleManagementTest extends TestCase
{
    use RefreshDatabase;

    private Role $adminRole;

    private Role $userRole;

    protected function setUp(): void
    {
        parent::setUp();

        $this->adminRole = Role::factory()->admin()->create();
        $this->userRole = Role::factory()->user()->create();
    }

    public function test_admin_can_list_roles(): void
    {
        $admin = User::factory()->create();
        $admin->roles()->attach($this->adminRole);

        Passport::actingAs($admin);

        $response = $this->getJson('/api/v1/roles');

        $response->assertOk()
            ->assertJsonCount(2, 'data')
            ->assertJsonStructure([
                'data' => [
                    '*' => ['id', 'name', 'created_at', 'updated_at'],
                ],
            ]);
    }

    public function test_non_admin_cannot_list_roles(): void
    {
        $user = User::factory()->create();
        $user->roles()->attach($this->userRole);

        Passport::actingAs($user);

        $response = $this->getJson('/api/v1/roles');

        $response->assertStatus(403);
    }

    public function test_unauthenticated_user_cannot_list_roles(): void
    {
        $response = $this->getJson('/api/v1/roles');

        $response->assertStatus(401);
    }

    public function test_admin_can_assign_roles_to_user(): void
    {
        $admin = User::factory()->create();
        $admin->roles()->attach($this->adminRole);

        $user = User::factory()->create();

        Passport::actingAs($admin);

        $response = $this->postJson("/api/v1/users/{$user->id}/roles", [
            'roles' => ['admin', 'user'],
        ]);

        $response->assertOk()
            ->assertJson(['message' => 'Roles assigned successfully.']);

        $this->assertTrue($user->fresh()->hasRole('admin'));
        $this->assertTrue($user->fresh()->hasRole('user'));
    }

    public function test_non_admin_cannot_assign_roles(): void
    {
        $user = User::factory()->create();
        $user->roles()->attach($this->userRole);

        $targetUser = User::factory()->create();

        Passport::actingAs($user);

        $response = $this->postJson("/api/v1/users/{$targetUser->id}/roles", [
            'roles' => ['admin'],
        ]);

        $response->assertStatus(403);
    }

    public function test_admin_can_remove_roles_from_user(): void
    {
        $admin = User::factory()->create();
        $admin->roles()->attach($this->adminRole);

        $user = User::factory()->create();
        $user->roles()->attach([$this->adminRole->id, $this->userRole->id]);

        Passport::actingAs($admin);

        $response = $this->deleteJson("/api/v1/users/{$user->id}/roles", [
            'roles' => ['admin'],
        ]);

        $response->assertOk()
            ->assertJson(['message' => 'Roles removed successfully.']);

        $this->assertFalse($user->fresh()->hasRole('admin'));
        $this->assertTrue($user->fresh()->hasRole('user'));
    }

    public function test_non_admin_cannot_remove_roles(): void
    {
        $user = User::factory()->create();
        $user->roles()->attach($this->userRole);

        $targetUser = User::factory()->create();
        $targetUser->roles()->attach($this->adminRole);

        Passport::actingAs($user);

        $response = $this->deleteJson("/api/v1/users/{$targetUser->id}/roles", [
            'roles' => ['admin'],
        ]);

        $response->assertStatus(403);
    }

    public function test_assign_roles_validates_invalid_role_names(): void
    {
        $admin = User::factory()->create();
        $admin->roles()->attach($this->adminRole);

        $user = User::factory()->create();

        Passport::actingAs($admin);

        $response = $this->postJson("/api/v1/users/{$user->id}/roles", [
            'roles' => ['nonexistent-role'],
        ]);

        $response->assertStatus(422)
            ->assertJsonValidationErrors(['roles.0']);
    }

    public function test_role_assignment_is_idempotent(): void
    {
        $admin = User::factory()->create();
        $admin->roles()->attach($this->adminRole);

        $user = User::factory()->create();
        $user->roles()->attach($this->userRole);

        Passport::actingAs($admin);

        $response = $this->postJson("/api/v1/users/{$user->id}/roles", [
            'roles' => ['user'],
        ]);

        $response->assertOk();

        $this->assertCount(1, $user->fresh()->roles);
    }
}
